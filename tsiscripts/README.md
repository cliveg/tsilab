# TSI Scripts

TSI Scripts are examples for managing the TSI Lab


## new-instance-name.sh
This example updates any **instance** without a name and assigns a Hierarchy if one is provided as a parameter, or one exists already, else creates a sample hierarchy

## Usage
The parameters include: 
- ``tsi environment name``
- ``tsi hierarchy id`` (optional - will create sample if one doesnt exist)

```bash
wget -O new-instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/new-instance-name.sh
bash ./new-instance-name.sh <tsi environment name> <tsi hierarchy id>
```

## Example

```bash
wget -O new-instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/new-instance-name.sh
bash ./new-instance-name.sh mytsilab123
```


## instance-name.sh
This another example to update and overwrite all instances **Name** property based on the tagid, while leaving all other properties intact including Hierarchy. You could extend this example to use substring elements of the tagid to create hierarchy of properties


## Example

```bash
wget -O instance-name.sh https://raw.githubusercontent.com/cliveg/tsilab/master/tsiscripts/new-instance-name.sh
bash ./instance-name.sh MyP! mytsilab123
```

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.


## License
[MIT](https://choosealicense.com/licenses/mit/)