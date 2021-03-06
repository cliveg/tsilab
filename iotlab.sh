#!/bin/bash
ADMINPASSWORD=$1
DEVICE=$2
LOCATION="westus2"
OPCSIM="https://www.prosysopc.com/opcua/apps/JavaServer/dist/4.0.2-108/prosys-opc-ua-simulation-server-linux-4.0.2-108.sh"
# example: bash ./iotlab.sh LongP@ssword1234 myiotlab123

echo - IoT Lab - 
echo $# parameters passed
if [ $# = 0 ]; then echo "No parameters found. Parameters = <password> <deviceid> <your-remote-public-IP> adb"; exit ; fi
if [ $# = 1 ]; then echo "Missing parameters. Parameters = <password> <deviceid> <your-remote-public-IP> adb"; fi

export VMEXIST=$(az vm list -g $DEVICE --query [].name -o tsv)
export dataAccessID=$(az resource show -g $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments -n $DEVICE --query 'properties.dataAccessId' -o tsv)
export subscriptionid=$(az account show --query id -o tsv)
export IOTHUBNAME="${DEVICE//_}"
export ACCESSPOLICYCONTRIBUTOROBJECTID=$(az ad signed-in-user show --query objectId --output tsv)

if [ $(az group exists -n $DEVICE) = false ]; then
    echo CREATE: Resource Group
    az group create --name $DEVICE --location $LOCATION
    az deployment group create -g $DEVICE --template-uri "https://raw.githubusercontent.com/cliveg/tsilab/master/azuredeploy.json" --parameters bastion-host-name=$DEVICE databricks-workspaceName=$DEVICE vnet-new-or-existing=new iotHubName=$IOTHUBNAME environmentTimeSeriesIdProperties='[{"name":"DisplayName","type":"string"}]' environmentName=$DEVICE environmentDisplayName=$DEVICE eventSourceTimestampPropertyName=trendtime warmStoreDataRetention=P31D vmAdminUsername=azureuser vmAdminPassword=$ADMINPASSWORD accessPolicyContributorObjectIds="[\"$ACCESSPOLICYCONTRIBUTOROBJECTID\"]"
    export newvm="true"
else
    # Check if VM exists
    if [[ $VMEXIST == *"$IOTHUBNAME"* ]]; then echo CHECK: VM Found; else export newvm="true"; echo CHECK: VM Not Found; fi
    if [[ $dataAccessID == "" ]]; then echo "CHECK: TSI Not Found"; else echo "CHECK: TSI Found"; fi

    read -r -p "Resource Group and above resources already exist, do you want to continue ? [y/N] " response
    response=${response,,}    # tolower
    if [[ "$response" =~ ^(yes|y)$ ]]; then echo Will Continue...; else exit; fi
    az deployment group create -g $DEVICE --template-uri "https://raw.githubusercontent.com/cliveg/tsilab/master/azuredeploy.json" --parameters bastion-host-name=$DEVICE databricks-workspaceName=$DEVICE vnet-new-or-existing=new iotHubName=$IOTHUBNAME environmentTimeSeriesIdProperties='[{"name":"DisplayName","type":"string"}]' environmentName=$DEVICE environmentDisplayName=$DEVICE eventSourceTimestampPropertyName=trendtime warmStoreDataRetention=P31D vmAdminUsername=azureuser vmAdminPassword=$ADMINPASSWORD accessPolicyContributorObjectIds="[\"$ACCESSPOLICYCONTRIBUTOROBJECTID\"]"
fi

az extension add --name azure-cli-iot-ext

if [[ $dataAccessID == "" ]]; then
    export dataAccessID=$(az resource show -g $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments -n $DEVICE --query 'properties.dataAccessId' -o tsv)
    echo Create: IoT Device Identity
    az iot hub device-identity create --hub-name $IOTHUBNAME --device-id $IOTHUBNAME --edge-enabled
    wget -O edgedevicemanifest.json 'https://raw.githubusercontent.com/cliveg/tsilab/master/config/edgedevicemanifest_latest.json'
    az iot edge set-modules --device-id $IOTHUBNAME --hub-name $IOTHUBNAME --content edgedevicemanifest.json
fi 

export SHAREDACCESSKEY=$(az iot hub policy show --hub-name $IOTHUBNAME --name iothubowner --query primaryKey -o tsv)
export CONNECTIONSTRING=$(az iot hub device-identity show-connection-string --device-id $IOTHUBNAME --hub-name $IOTHUBNAME --query 'connectionString' -o tsv)

export VMEXIST=$(az vm list -g $DEVICE --query [].name -o tsv)
if [[ $VMEXIST != *"$IOTHUBNAME"* ]]; then echo "Error: VM not found so exiting."; exit; fi

export PRIVATEIP=$(az vm show -d -g $DEVICE -n $IOTHUBNAME --query privateIps -o tsv)

if [[ $newvm == "true" ]]; then
    echo Configure: VM configuration of IoT Edge
    az vm run-command invoke -g $DEVICE -n $IOTHUBNAME --command-id RunShellScript --script "/etc/iotedge/configedge.sh '$CONNECTIONSTRING'"
    az vm run-command invoke -g $DEVICE -n $IOTHUBNAME --command-id RunShellScript --script "sudo mkdir /iiotedge && sudo wget -O /iiotedge/prosys.sh $OPCSIM && sudo chmod u=x /iiotedge/prosys.sh && sudo apt-get update && sudo apt-get -y install xfce4 xrdp zip && sudo systemctl enable xrdp && printf 'o\n\n\n\n1\n/opt/prosys-opc-ua-simulation-server\ny\n' > /iiotedge/prosys.txt ; sudo chown 1000 /iiotedge && sudo chmod 700 /iiotedge && sudo mkdir /etc/iotedge/storage && sudo chown 1000 /etc/iotedge/storage && sudo chmod 700 /etc/iotedge/storage ; printf '[{\"EndpointUrl\":\"opc.tcp://$PRIVATEIP:53530/OPCUA/SimulationServer\",\"UseSecurity\":false,\"OpcNodes\":[{\"Id\":\"ns=3;s=Counter\"},{\"Id\":\"ns=3;s=Expression\"},{\"Id\":\"ns=3;s=Random\"},{\"Id\":\"ns=3;s=Sawtooth\"},{\"Id\":\"ns=3;s=Sinusoid\"},{\"Id\":\"ns=3;s=Square\"},{\"Id\":\"ns=3;s=Triangle\"}]}]' > /iiotedge/pn.json ; printf 'net.ipv6.conf.all.disable_ipv6 = 1 \n net.ipv6.conf.default.disable_ipv6 = 1 \n net.ipv6.conf.lo.disable_ipv6 = 1 \n ' | sudo tee -a /etc/sysctl.d/60-ipv6-disable.conf ; sudo service procps restart"
    az vm run-command invoke -g $DEVICE -n $IOTHUBNAME --command-id RunShellScript --script "sudo systemctl restart iotedge"
    echo Install: OPC Simulation Server Software
    az vm run-command invoke -g $DEVICE -n $IOTHUBNAME --command-id RunShellScript --script "/iiotedge/prosys.sh </iiotedge/prosys.txt"
fi

echo 'Next Steps:'
echo '1. Use Bastion to the Windows VM and then Remote Desktop: mstsc /v:'$PRIVATEIP' Login: azureuser and Password:' $ADMINPASSWORD
echo '2. Start the OPC Server Simulator by opening File System, /opt/optsys-opc-ua-simulation-server and double-click ProSys OPC UA Simulation'
echo '3. After the OPC Simulator is started run these scripts to update TSI Model for the newly seen timeseries instances:'
echo 'wget -O new-instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/new-instance-name.sh'
echo 'bash ./new-instance-name.sh' $DEVICE
echo
echo 'wget -O instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/instance-name.sh'
echo 'bash ./instance-name.sh' $DEVICE
echo
echo '4. Open the TSI and explore your data: https://insights.timeseries.azure.com/preview?environmentId='$dataAccessID
