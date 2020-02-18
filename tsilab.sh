#!/bin/bash
echo There were $# parameters passed.

if [ $# = 0 ]; then echo "No parameters found. Parameters = <password> <deviceid> <your-remote-public-IP>"; exit ; fi
if [ $# = 1 ]; then echo "Missing parameters. Parameters = <password> <deviceid> <your-remote-public-IP>"; fi
if [ $# = 2 ]; then echo "You need to update the NSG (Network Security Group) on completion update the 4.4.4.4 to either your remote public or private IP address (or * for any) so you can RDP and SSH to the VM."; fi

#Region, trusted IP for RDP, Public IP, VNET

ADMINPASSWORD=$1
DEVICE=$2
export ACCESSPOLICYREADEROBJECTID=$(az ad signed-in-user show --query objectId --output tsv)

az extension add --name azure-cli-iot-ext

echo Creating Resource Group
az group create --name $DEVICE --location westus2

echo Creating IoTHub and TSI Environment
az group deployment create -g $DEVICE --template-uri "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-timeseriesinsights-environment-payg-with-iothub/azuredeploy.json" --parameters iotHubName=$DEVICE environmentTimeSeriesIdProperties='({"name":"iothub-connection-device-id","type":"string"},{"name":"tagid","type":"string"})' environmentName=$DEVICE environmentDisplayName=$DEVICE eventSourceTimestampPropertyName=trendtime warmStoreDataRetention=P31D accessPolicyContributorObjectIds="[\"$ACCESSPOLICYREADEROBJECTID\"]"
export dataAccessID=$(az resource show -g $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments -n $DEVICE --query 'properties.dataAccessId' -o tsv)

echo Creating IoT Device Identity
az iot hub device-identity create --hub-name $DEVICE --device-id $DEVICE --edge-enabled
export SHAREDACCESSKEY=$(az iot hub policy show --hub-name $DEVICE --name iothubowner --query primaryKey -o tsv)
export CONNECTIONSTRING=$(az iot hub device-identity show-connection-string --device-id $DEVICE --hub-name $DEVICE --query 'connectionString' -o tsv)
wget -O edgedevicemanifest.json 'https://raw.githubusercontent.com/cliveg/tsilab/master/config/edgedevicemanifest.json'
az iot edge set-modules --device-id $DEVICE --hub-name $DEVICE --content edgedevicemanifest.json

echo Creating VM for IoT Edge and OPC Simulator
az vm image terms accept --urn microsoft_iot_edge:iot_edge_vm_ubuntu:ubuntu_1604_edgeruntimeonly:latest

# This approach will create its own VNET with a Public IP (for no Public IP add --public-ip-address "")
az vm create --resource-group $DEVICE --name $DEVICE --image microsoft_iot_edge:iot_edge_vm_ubuntu:ubuntu_1604_edgeruntimeonly:latest --admin-username azureuser --authentication-type all --admin-password $ADMINPASSWORD --generate-ssh-keys --nsg $DEVICE --size Standard_B2ms 
if [ $# = 3 ]; then
    echo Updating Firewall for your remote ip $3 
    az network nsg rule update -g $DEVICE --nsg-name $DEVICE -n default-allow-ssh --source-address-prefixes $3 --destination-port-ranges 22 3389
else
    az network nsg rule update -g $DEVICE --nsg-name $DEVICE -n default-allow-ssh --source-address-prefixes '4.4.4.4' --destination-port-ranges 22 3389
fi

export PRIVATEIP=$(az vm show -d -g $DEVICE -n $DEVICE --query privateIps -o tsv)
export PUBLICIP=$(az vm show -d -g $DEVICE -n $DEVICE --query publicIps -o tsv)
echo - configureEdge
az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "/etc/iotedge/configedge.sh '$CONNECTIONSTRING'"
az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "sudo mkdir /iiotedge && sudo wget -O /iiotedge/prosys.sh https://www.prosysopc.com/opcua/apps/JavaServer/dist/4.0.2-108/prosys-opc-ua-simulation-server-linux-4.0.2-108.sh && sudo chmod u=x /iiotedge/prosys.sh && sudo apt-get update && sudo apt-get -y install xfce4 xrdp zip && sudo systemctl enable xrdp && printf 'o\n\n\n\n1\n/opt/prosys-opc-ua-simulation-server\ny\n' > /iiotedge/prosys.txt ; sudo /etc/init.d/xrdp stop; sudo /etc/init.d/xrdp start ; sudo chown 1000 /iiotedge && sudo chmod 700 /iiotedge && sudo mkdir /etc/iotedge/storage && sudo chown 1000 /etc/iotedge/storage && sudo chmod 700 /etc/iotedge/storage ; printf '[{\"EndpointUrl\":\"opc.tcp://$PRIVATEIP:53530/OPCUA/SimulationServer\",\"UseSecurity\":false,\"OpcNodes\":[{\"Id\":\"i=2258\"},{\"Id\":\"ns=3;s=Counter\"},{\"Id\":\"ns=3;s=Expression\"},{\"Id\":\"ns=3;s=Random\"},{\"Id\":\"ns=3;s=Sawtooth\"},{\"Id\":\"ns=3;s=Sinusoid\"},{\"Id\":\"ns=3;s=Square\"},{\"Id\":\"ns=3;s=Triangle\"}]}]' > /iiotedge/pn.json ; printf 'net.ipv6.conf.all.disable_ipv6 = 1 \n net.ipv6.conf.default.disable_ipv6 = 1 \n net.ipv6.conf.lo.disable_ipv6 = 1 \n ' | sudo tee -a /etc/sysctl.d/60-ipv6-disable.conf ; sudo service procps restart"

az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "printf '{\"Defaults\":{\"EndpointUrl\":{\"Publish\":false,\"Pattern\":\"(.*)\",\"Name\":\"EndpointUrl\"},\"NodeId\":{\"Publish\":false,\"Name\":\"NodeId\"},\"MonitoredItem\":{\"Flat\":true,\"ApplicationUri\":{\"Publish\":false,\"Name\":\"collector\",\"Pattern\":\"urn://([^/]+)\"},\"DisplayName\":{\"Publish\":true,\"Pattern\":\"ns=.;s=(.*)\",\"Name\":\"tagid\"}},\"Value\":{\"Flat\":true,\"Value\":{\"Publish\":true,\"Name\":\"value\"},\"SourceTimestamp\":{\"Publish\":true,\"Name\":\"trendtime\"},\"StatusCode\":{\"Publish\":true,\"Name\":\"statuscode\"},\"Status\":{\"Publish\":true,\"Name\":\"status\"}}},}' > /iiotedge/telemetryconfiguration.json"
az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "sudo systemctl restart iotedge"
echo - install OPC Simulation Server
az vm run-command invoke -g $DEVICE -n $DEVICE --command-id RunShellScript --script "/iiotedge/prosys.sh </iiotedge/prosys.txt"
echo Verify the publisher module is running by typing: sudo docker ps
echo Verify the publisher module is connected to the simulator by entering Expert mode from the Options menu and going to the Connection Log tab
echo Open TSI Explorer from the TSI environment in Azure Portal and check your data is flowing
echo https://insights.timeseries.azure.com/preview?environmentId=$dataAccessID
echo Remote Desktop to start the OPC Simulator: mstsc /v:$PUBLICIP