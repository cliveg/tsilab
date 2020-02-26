#!/bin/bash
ADMINPASSWORD=$1
DEVICE=$2
LOCATION="westus2"
OPCSIM="https://www.prosysopc.com/opcua/apps/JavaServer/dist/4.0.2-108/prosys-opc-ua-simulation-server-linux-4.0.2-108.sh"
# example: bash ./tsilab.sh LongP@ssword1234 mytsilab123 50.1.2.3

echo - TSI Lab - 
echo $# parameters passed
if [ $# = 0 ]; then echo "No parameters found. Parameters = <password> <deviceid> <your-remote-public-IP> adb"; exit ; fi
if [ $# = 1 ]; then echo "Missing parameters. Parameters = <password> <deviceid> <your-remote-public-IP> adb"; fi
if [ $# = 2 ]; then echo "You need to update the NSG (Network Security Group) on completion update the 4.4.4.4 to either your remote public or private IP address (or * for any) so you can RDP and SSH to the VM."; fi

# Authenticate to allow AZ REST to manage databricks cluster
export cloudShellID=$(az account show --query 'user.cloudShellID' -o tsv)
if [ -n "$cloudShellID" ]; then
    echo "CloudShell: Not Authenticated"
    az login
fi

export VMEXIST=$(az vm list -g $DEVICE --query [].name -o tsv)
export appid=$(az ad app list --filter "displayName eq '$DEVICE'" --query [].appId -o tsv)
export dataAccessID=$(az resource show -g $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments -n $DEVICE --query 'properties.dataAccessId' -o tsv)
export adbstate=$(az resource show -g $DEVICE --resource-type Microsoft.Databricks/workspaces -n $DEVICE --query 'properties.provisioningState' -o tsv)

if [ $(az group exists -n $DEVICE) = false ]; then
    echo CREATE: Resource Group
    az group create --name $DEVICE --location $LOCATION
else
    # Check if VM exists
    if [[ $VMEXIST == *"$DEVICE"* ]]; then echo CHECK: VM Found; else echo CHECK: VM Not Found; fi
    if [ -n "$appid" ]; then echo "CHECK: AppID Found"; else echo "CHECK: AppID Not Found"; fi
    if [[ $dataAccessID == "" ]]; then echo "CHECK: TSI Not Found"; else echo "CHECK: TSI Found"; fi
    if [[ $adbstate == "Succeeded" ]]; then echo "CHECK: Databricks Found"; else echo "CHECK: Databricks Not Found"; fi
    if [ -n "$cloudShellID" ]; then echo "CHECK: CloudShell Not Authenticated"; else echo "CHECK: CloudShell Authenticated"; fi

    read -r -p "Resource Group and above resources already exist, do you want to continue ? [y/N] " response
    response=${response,,}    # tolower
    if [[ "$response" =~ ^(yes|y)$ ]]; then echo Will Continue...; else exit; fi
fi

az extension add --name azure-cli-iot-ext

if [ -n "$appid" ]; then
    # Reset the service principal secret
    echo "Application ID Already Exists, resetting secret for appid: $appid"
    serverApplicationId=$appid
    serverApplicationSecret=$(az ad sp credential reset --name $serverApplicationId --credential-description "TSIPassword" --query password -o tsv)
else
    echo "Creating Az AD Application"
    serverApplicationId=$(az ad app create --display-name "${DEVICE}" --identifier-uris "https://${DEVICE}" --reply-urls "https://${DEVICE}" --required-resource-accesses '[{"resourceAppId":"120d688d-1518-4cf7-bd38-182f158850b6","resourceAccess":[{"id":"a3a77dfe-67a4-4373-b02a-dfe8485e2248","type":"Scope"}]}]' --query appId -o tsv)
    # Create a service principal for the Azure AD application
    az ad sp create --id $serverApplicationId
fi

# Create Azure Databricks Workspace
if [[ $adbstate != "Succeeded" ]]; then
    echo Create: Azure Databricks Service
    az group deployment create -g $DEVICE --template-uri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-databricks-all-in-one-template-for-vnet-injection/azuredeploy.json" --parameters nsgName=databricks-nsg vnetName=databricks-vnet workspaceName=$DEVICE privateSubnetName=private-subnet publicSubnetName=public-subnet pricingTier=trial location=$LOCATION vnetCidr=10.179.0.0/16 privateSubnetCidr=10.179.0.0/18 publicSubnetCidr=10.179.64.0/18
fi
wsId=$(az resource show --resource-type Microsoft.Databricks/workspaces -g $DEVICE -n $DEVICE --query id -o tsv)

# Get the User and Service Principal to include in TSI dataaccess policy
export ACCESSPOLICYREADEROBJECTID=$(az ad sp show --id $serverApplicationId | jq -r .objectId)
export ACCESSPOLICYCONTRIBUTOROBJECTID=$(az ad signed-in-user show --query objectId --output tsv)
export USERID=$(az ad signed-in-user show --query userPrincipalName --output tsv)
if [[ $serverApplicationId != "" ]]; then serverApplicationSecret=$(az ad sp credential reset --name $serverApplicationId --credential-description "TSIPassword" --query password -o tsv); else serverApplicationSecret=""; fi

if [[ $dataAccessID == "" ]]; then
    echo Create: IoTHub and TSI Environment
    az group deployment create -g $DEVICE --template-uri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-timeseriesinsights-environment-payg-with-iothub/azuredeploy.json" --parameters iotHubName=$DEVICE environmentTimeSeriesIdProperties='({"name":"iothub-connection-device-id","type":"string"},{"name":"tagid","type":"string"})' environmentName=$DEVICE environmentDisplayName=$DEVICE eventSourceTimestampPropertyName=trendtime warmStoreDataRetention=P31D accessPolicyReaderObjectIds="[\"$ACCESSPOLICYREADEROBJECTID\"]" accessPolicyContributorObjectIds="[\"$ACCESSPOLICYCONTRIBUTOROBJECTID\"]"
    export dataAccessID=$(az resource show -g $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments -n $DEVICE --query 'properties.dataAccessId' -o tsv)

    echo Create: IoT Device Identity
    az iot hub device-identity create --hub-name $DEVICE --device-id $DEVICE --edge-enabled
    wget -O edgedevicemanifest.json 'https://raw.githubusercontent.com/cliveg/tsilab/master/config/edgedevicemanifest.json'
    az iot edge set-modules --device-id $DEVICE --hub-name $DEVICE --content edgedevicemanifest.json

fi 

export SHAREDACCESSKEY=$(az iot hub policy show --hub-name $DEVICE --name iothubowner --query primaryKey -o tsv)
export CONNECTIONSTRING=$(az iot hub device-identity show-connection-string --device-id $DEVICE --hub-name $DEVICE --query 'connectionString' -o tsv)

echo Generating Notebook for TSI Spark Connector
export StorageAccountName=$(az resource show -g $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments -n $DEVICE --query 'properties.storageConfiguration.accountName' -o tsv)
export StorageAccountKey=$(az storage account keys list -g $DEVICE -n $StorageAccountName --query [0].value -o tsv)
export TenantId=$(az account get-access-token --query tenant --output tsv)

# Create Databricks Secret Scope for TSI
az rest --method post --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/scopes/create --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "initial_manage_principal": "users"}'

# Create Databricks Secrets for TSI
az rest --method POST --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/put --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "key": "StorageAccountName", "string_value": "'$StorageAccountName'"}'
az rest --method POST --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/put --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "key": "TSI_APP_ID", "string_value": "'$serverApplicationId'"}'
az rest --method POST --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/put --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "key": "TSI_APP_KEY", "string_value": "'$serverApplicationSecret'"}'
az rest --method POST --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/put --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "key": "TSI_TENANT_ID", "string_value": "'$TenantId'"}'
az rest --method POST --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/put --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "key": "TSI_STORAGE_KEY", "string_value": "'$StorageAccountKey'"}'
az rest --method POST --uri https://$LOCATION.azuredatabricks.net/api/2.0/secrets/put --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body '{"scope":"tsi", "key": "TSI_ENVIRONMENT_FQDN", "string_value": "'$dataAccessID'.env.timeseries.azure.com"}'

wget -O tsi_notebook.scala 'https://cliveguswest2.blob.core.windows.net/tsilab/TSISparkDataConnector.0.3.scala'

value=$(base64< tsi_notebook.scala)
echo '{ "content": "'$value'", "file_type": "scala", "language": "SCALA", "overwrite": "true", "path": "/Users/'$USERID'/TSI" }'> tsinotebook.json

#upload Notebook
az rest --method post --uri https://$LOCATION.azuredatabricks.net/api/2.0/workspace/import --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --headers "X-Databricks-Azure-Workspace-Resource-Id"=$wsId --body @tsinotebook.json

if [[ $VMEXIST != *"$DEVICE"* ]]; then
    echo Create: VM for IoT Edge and OPC Simulator
    newvm="true"
    az vm image terms accept --urn microsoft_iot_edge:iot_edge_vm_ubuntu:ubuntu_1604_edgeruntimeonly:latest

    # for no Public IP add --public-ip-address ""
    echo CREATE: VM
    az vm create --resource-group $DEVICE --name $DEVICE --image microsoft_iot_edge:iot_edge_vm_ubuntu:ubuntu_1604_edgeruntimeonly:latest --admin-username azureuser --authentication-type all --admin-password $ADMINPASSWORD --generate-ssh-keys --nsg "/subscriptions/d6670526-5bdd-40db-9865-f3b1bd3e7d71/resourceGroups/$DEVICE/providers/Microsoft.Network/networkSecurityGroups/databricks-nsg" --size Standard_B2ms

    if [ $# -gt 2 ]; then
        echo "UPDATE: NSG  for remote ip" $3
        az network nsg rule create -g $DEVICE --nsg-name databricks-nsg -n default-allow-ssh --priority 1000 --source-address-prefixes $3 --destination-port-ranges 22 3389
    else
        echo "UPDATE: NSG  for remote ip 4.4.4.4"
        az network nsg rule create -g $DEVICE --nsg-name databricks-nsg -n default-allow-ssh --priority 1000 --source-address-prefixes '4.4.4.4' --destination-port-ranges 22 3389
    fi
fi

export VMEXIST=$(az vm list -g $DEVICE --query [].name -o tsv)
if [[ $VMEXIST != *"$DEVICE"* ]]; then echo "Error: VM not found so exiting."; exit; fi

export PRIVATEIP=$(az vm show -d -g $DEVICE -n $DEVICE --query privateIps -o tsv)
export PUBLICIP=$(az vm show -d -g $DEVICE -n $DEVICE --query publicIps -o tsv)

if [[ $newvm == "true" ]]; then
    echo Configure: VM configuration of IoT Edge
    az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "/etc/iotedge/configedge.sh '$CONNECTIONSTRING'"
    az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "sudo mkdir /iiotedge && sudo wget -O /iiotedge/prosys.sh $OPCSIM && sudo chmod u=x /iiotedge/prosys.sh && sudo apt-get update && sudo apt-get -y install xfce4 xrdp zip && sudo systemctl enable xrdp && printf 'o\n\n\n\n1\n/opt/prosys-opc-ua-simulation-server\ny\n' > /iiotedge/prosys.txt ; sudo chown 1000 /iiotedge && sudo chmod 700 /iiotedge && sudo mkdir /etc/iotedge/storage && sudo chown 1000 /etc/iotedge/storage && sudo chmod 700 /etc/iotedge/storage ; printf '[{\"EndpointUrl\":\"opc.tcp://$PRIVATEIP:53530/OPCUA/SimulationServer\",\"UseSecurity\":false,\"OpcNodes\":[{\"Id\":\"ns=3;s=Counter\"},{\"Id\":\"ns=3;s=Expression\"},{\"Id\":\"ns=3;s=Random\"},{\"Id\":\"ns=3;s=Sawtooth\"},{\"Id\":\"ns=3;s=Sinusoid\"},{\"Id\":\"ns=3;s=Square\"},{\"Id\":\"ns=3;s=Triangle\"}]}]' > /iiotedge/pn.json ; printf 'net.ipv6.conf.all.disable_ipv6 = 1 \n net.ipv6.conf.default.disable_ipv6 = 1 \n net.ipv6.conf.lo.disable_ipv6 = 1 \n ' | sudo tee -a /etc/sysctl.d/60-ipv6-disable.conf ; sudo service procps restart"
    az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "printf '{\"Defaults\":{\"EndpointUrl\":{\"Publish\":false,\"Pattern\":\"(.*)\",\"Name\":\"EndpointUrl\"},\"NodeId\":{\"Publish\":false,\"Name\":\"NodeId\"},\"MonitoredItem\":{\"Flat\":true,\"ApplicationUri\":{\"Publish\":false,\"Name\":\"collector\",\"Pattern\":\"urn://([^/]+)\"},\"DisplayName\":{\"Publish\":true,\"Pattern\":\"ns=.;s=(.*)\",\"Name\":\"tagid\"}},\"Value\":{\"Flat\":true,\"Value\":{\"Publish\":true,\"Name\":\"value\"},\"SourceTimestamp\":{\"Publish\":true,\"Name\":\"trendtime\"},\"StatusCode\":{\"Publish\":true,\"Name\":\"statuscode\"},\"Status\":{\"Publish\":true,\"Name\":\"status\"}}},}' > /iiotedge/telemetryconfiguration.json"
    az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "sudo systemctl restart iotedge"
    echo Install: OPC Simulation Server Software
    az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "/iiotedge/prosys.sh </iiotedge/prosys.txt"
fi

echo 'Next Steps:'
echo '1. Remote Desktop: mstsc /v:'$PUBLICIP' Login: azureuser and Password:' $ADMINPASSWORD
echo '2. Start the OPC Server Simulator by opening File System, /opt/optsys-opc-ua-simulation-server and double-click ProSys OPC UA Simulation'
echo '3. After the OPC Simulator is started run these scripts to update TSI Model for the newly seen timeseries instances:'
echo 'wget -O new-instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/new-instance-name.sh'
echo 'bash ./new-instance-name.sh' $DEVICE
echo
echo 'wget -O instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/instance-name.sh'
echo 'bash ./instance-name.sh' $DEVICE
echo
echo '4. Open the TSI and explore your data: https://insights.timeseries.azure.com/preview?environmentId='$dataAccessID
echo '5. Open the Azure Databricks Workspace: https://'$LOCATION'.azuredatabricks.net/ '
echo '- Click Import Library and drag and drop to upload your JAR, once uploaded Click Create, and Check Install automatically on all clusters'
echo '- Go to Clusters, Click Create Cluster, for the lowest cost option Uncheck Enable autoscaling, set Worker Type to Standard_F4s, and set Workers to 1'
echo '- Go to Workspace, and try out the example Notebook: TSI'
