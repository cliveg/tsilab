# Clean Up OPC Server Identities


OPC Server identity's include redundant text in the DisplayName e.g ```ns=2;s=Counter``` where you only need keep i.e. ```Counter```. Keeping a long identity increases storage and make it hard to read/display. Its best to fix this early when establishing a naming standard.

It's critical to have unique identity's, but remember IoT Hub adds properties you can use for that. e.g. the IoT Hub Device Id to help maintain a unique id e.g. Time Series Insights at deploy time allows you to configure the ```Time Series ID Property``` e.g. 
```iothub-connection-device-id, tagid```

*** Highly Recommend Testing this all out before going too far with a deployment as you don't want to change id's once you are building solutions on top of the data. In Time Series Insights you it has a Model containing Instances for each id - this is where you want to manage naming once data is flowing as you can update this anytime without impacting the raw streamed data identity ***

Another example with a longer id DisplayName like ```ns=2;s=CONTOSO_POC.ECP.CONTOSO_ECP.CONTOSO_OPC_ECP.U1_TEST.EE_Oxy_Inlet``` where you only want ```CONTOSO.U1_TEST.EE_Oxy_Inlet```

 when consuming from IoT Edge e.g. from Time Series Insights (TSI), Stream Analytics, Functions, Data Explorer (ADX), etc.

You can update the DisplayName of the id at the OPC Server, but if you can't control this you can do it in the IoT Edge OPC Publisher Module.

1. Telemetry Configuration file : configure the 'DisplayName' 'Pattern' property with a regular expression
2. Published Nodes file : add a 'DisplayName' property to each identity you want to modify

## IoT Edge OPC Publisher Module - Telemetry Configuration File

To edit, SSH to the IoT Edge VM to edit e.g. 
```bash
ssh azureuser@123.345.789.123
sudo nano /iiotedge/telemetryconfiguration.json
```

As part of this lab we already setup a regular expression for the 'Pattern' property of 'DisplayName' to: ```ns=.;s=(.*)``` this removes ```ns=2;s=``` which is a good start!

To develop regular expressions I found this site helpful: [RegExr](ttps://regexr.com/)

Example for specific id's:
```ns=.;s=(Counter|Triangle|Sinusoid|Random|Expression|Sawtooth|Square)``` which trims only named id's e.g. ```ns=2;s=Counter``` = ```Counter```

Example for long DisplayNames containing separators:
```'ns=.;s=[^.]*.[^.]*.[^.]*.([^_]*)[^.]*(.*)``` which would translate ```ns=2;s=CONTOSO_POC.ECP.CONTOSO_ECP.CONTOSO_OPC_ECP.U1_TEST.EE_Oxy_Inlet``` to ```CONTOSO.U1_TEST.EE_Oxy_Inlet```

Example of my current setting combining multiple regular expressions:
```python
      "DisplayName": {
        "Publish": true,
        "Pattern": "ns=.;s=(Counter|Triangle|Sinusoid|Random|Expression|Sawtooth|Square)|ns=.;s=[^.]*.[^.]*.[^.]*.([^_]*)[^.]*(.*)",
        "Name": "tagid"
      }
```

Restart the OPC Publisher Module after editing: ```sudo iotedge restart publisher```


Monitor the updated data from Azure Cloud Shell/CLI: ```az iot hub monitor-events --hub-name <hub name> --consumer-group <optional>```

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License
[MIT](https://choosealicense.com/licenses/mit/)