# TSI Lab

TSI Lab is Quickstart example of an OPC UA Server sending data through IoT Edge to Azure Time Series Insights (Preview PAYG).


## Getting Started

1. In Azure Portal open Azure Cloud Shell (Bash) and paste the wget and bash commands based off the example below.

2. After completion use Remote Desktop and connect to the VM, with the user name: azureuser

3. Start the OPC Server Simulator by opening File System, /opt/optsys-opc-ua-simulation-server and double-click ProSys OPC UA Simulation.

4. Open TSI Explorer from the TSI environment in Azure Portal and check your data is flowing


To diagnose:
1. Verify the publisher module is running: sudo docker ps
2. Verify the publisher module is connected to the simulator: Enter 'Expert Mode' from the Options menu, and goto the 'Connection Log' tab
3. Examine the IoT Edge OPC Publisher logs: sudo docker logs publisher


## Usage
The parameters include: 
- Password (for the VM)
- EnvironmentName (use something unique each time, and unique to you as this name is used for all resources including the storage account)
- AllowedRemoteIPAddress (discover this using [IPIFY](https://api.ipify.org). If you omit this parameter you can update the NSG Rule later).

```bash
wget -O tsilab.sh https://raw.githubusercontent.com/cliveg/tsilab/master/config/edgedevicemanifest.json/tsilab.sh
bash ./tsilab.sh <Password> <EnvironmentName> <AllowedRemoteIPAddress>
```

## Example

```bash
wget -O tsilab.sh https://raw.githubusercontent.com/cliveg/tsilab/master/config/edgedevicemanifest.json/tsilab.sh
bash ./tsilab.sh MyP!ssw0rdIs123 mytsilab123 50.1.2.3
```


## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.


## License
[MIT](https://choosealicense.com/licenses/mit/)