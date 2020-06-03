# TSI Lab

TSI Lab is Quickstart example of an OPC UA Server sending data through IoT Edge to Azure Time Series Insights (Preview PAYG).

Services Deployed include: Ubuntu VM (with IoT Edge, OPC Publisher Module, OPC Simulator), IoT Hub, TSI (with Long Term Storage), and Azure Databricks.

## Getting Started

1. In Azure Portal open Azure Cloud Shell (Bash) and paste the wget and bash commands based off the example below.

2. After completion use Remote Desktop and connect to the VM, with the user name: **azureuser**

3. Start the OPC Server Simulator by opening File System, **/opt/optsys-opc-ua-simulation-server** and double-click **ProSys OPC UA Simulation**.

4. Open **TSI Explorer** from the TSI environment in Azure Portal and check your data is flowing


To diagnose:
1. Verify the publisher module is running: sudo docker ps
2. Verify the publisher module is connected to the simulator: Enter '**Expert Mode**' from the **Options** menu, and goto the '**Connection Log**' tab
3. Examine the IoT Edge OPC Publisher logs: `sudo docker logs publisher`


## Usage
The parameters include: 
- ``Password`` (for the VM)
- ``EnvironmentName`` (use something unique each time, and unique to you as this name is used for all resources including the storage account)
- ``AllowedRemoteIPAddress`` (discover this using [IPIFY](https://api.ipify.org). If you omit this parameter you can update the NSG Rule later).

```bash
wget -O tsilab.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsilab.sh
bash ./tsilab.sh <Password> <EnvironmentName> <AllowedRemoteIPAddress>
```

## Example

```bash
wget -O tsilab.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsilab.sh
bash ./tsilab.sh LongP@ssword1234 mytsilab123 50.1.2.3
```

![Image](https://raw.githubusercontent.com/cliveg/tsilab/master/png/tsilab-opcsim.png)

![Image](https://raw.githubusercontent.com/cliveg/tsilab/master/png/tsilab-tsiexplorer.png)


## Cleanup
```bash
az group delete --name <Resource Group Name>
```

## Reference - Useful IoT Edge Commands
Enable Sysadmin - Avoid typing Sudo again!
```bash 
sudo -s
```
### Troubleshoot IoT Edge
[Azure Docs: Troubleshoot your IoT Edge Device](https://docs.microsoft.com/en-us/azure/iot-edge/troubleshoot)


List Status of Modules!
```bash 
iotedge list
```

Restart IoT Edge!
```bash 
systemctl restart iotedge
```

Restart Docker!!!
```bash 
systemctl restart docker
```
Docker Module Status
```bash 
docker ps
```
Docker Read Module Logs - make sure the module name matches
```bash 
docker logs edgeAgent --tail 100
docker logs edgeHub --tail 100
docker logs publisher
```

## Reference - Useful IoT Edge Links
### General
[Azure IoT-Edge Product Updates](https://azure.microsoft.com/en-us/updates/?product=iot-edge)
[Upgrade IoT Edge](https://docs.microsoft.com/en-us/azure/iot-edge/how-to-update-iot-edge)
[IoT Edge Agent Docker Image Tag List](https://mcr.microsoft.com/v2/azureiotedge-agent/tags/list)
[IoT Edge Hub Docker Image Tag List](https://mcr.microsoft.com/v2/azureiotedge-hub/tags/list)
[IoT Edge VM Deploy](https://github.com/azure/iotedge-vm-deploy)

### Industrial IoT Platform Related
#### OPC UA
[Azure Industrial IoT Platform](https://github.com/Azure/Industrial-IoT)
- [Deploying Azure Industrial IoT Platform and dependencies](https://github.com/Azure/Industrial-IoT/blob/master/docs/deploy/howto-deploy-all-in-one.md)
- [Telemetry Message Format](https://github.com/Azure/Industrial-IoT/blob/master/docs/dev-guides/telemetry-messages-format.md)
- [IoT Edge OPC Publisher Docker Image Tag List](https://mcr.microsoft.com/v2/iotedge/opc-publisher/tags/list)
[Discover and register servers and browse their address space, read and publish nodes via REST API in Postman](https://github.com/Azure/Industrial-IoT/blob/master/docs/tutorials/tut-use-postman.md)

#### OPC DA
OPC DA (known as OPC Classic in contrast to the newer OPC UA standard) is a protocol which is based on Microsoft COM technology, which means is has to run on Windows systems. Use a OPC UA to OPC DA bridge from a partner or using the OPC Foundation OPC UA to OPC DA wrapper available in the OPC Foundation github repository (https://github.com/OPCFoundation/UA-.NETStandard/blob/master/ComIOP/README.md) running outside if IoT Edge. 

- [Kepware](https://www.kepware.com/en-us/products/kepserverex/)
- [Matrikon](https://www.matrikonopc.com/opc-ua/products/opc-ua-tunneller.aspx)
- [Softing](https://data-intelligence.softing.com/products/opc-software-platform/datafeed-opc-suite/)
- [Capadata](https://www.copadata.com/en/news/news/available-now-from-microsoft-azure-marketplace-zenon-on-iot-edge-7824/)

### IoT Edge Monitoring
[Built-in logs collation and upload capability](https://aka.ms/iotedgelogpull) - On-demand Log Pull
[Continuous Log Push to Log Analytics](https://github.com/veyalla/logspout-loganalytics)
[Azure IoT Edge Hub experimental metrics](https://github.com/veyalla/ehm) 
[IoT GBBs Repo](https://github.com/AzureIoTGBB) -  edge monitoring example 

### IoT Edge High Availability
[Deploy IoT Edge on Kubernetes (Preview)](http://aka.ms/edgek8sdoc) - using it as a resilient, highly available infrastructure layer. 
Related [Scaling](https://microsoft.github.io/iotedge-k8s-doc/scaling.html) [How-To-Deploy](How to install IoT Edge on Kubernetes)


## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.


## License
[MIT](https://choosealicense.com/licenses/mit/)
