#!/bin/bash
# Update your IoT Modules
# mcr.microsoft.com/azureiotedge-hub:1.0.9.1
# mcr.microsoft.com/azureiotedge-agent:1.0.9.1
# Environment Variable: ExperimentalFeatures__Enabled = true  and  ExperimentalFeatures__EnableUploadLogs = true
# IMPORTANT: Set Environment Variables at the same time asthe new module version otherwise it wont take effect. 
#
# REF: https://github.com/Azure/iotedge/blob/master/doc/built-in-logs-pull.md
#
# example: bash ./iothubdevicelogs.sh <ResourceGroup> <IoT-Hub-Name> <IoT-Device-Name>

if [ $# != 3 ]; then echo "$# parameters passed, required <ResourceGroup-Name> <IoT-Hub-Name> <IoT-Device-Name>."; exit; fi
export RG=$1
export HUB=$2
export DEVICE=$3

CONTAINER="iotlogs"
SASSTART=`date +%Y-%m-%d`'T00:00:00Z'
EXPIRY=`date -d "+1 minute" +%Y-%m-%d`'T'`date -d "+1 minute" +%H:%M:%S`'Z'
# Get a storage account key
export SA=$(az resource show -g $RG --resource-type Microsoft.TimeSeriesInsights/environments -n $RG --query 'properties.storageConfiguration.accountName' -o tsv)

export StorageAccountKey=$(az storage account keys list -g $RG -n $SA --query [0].value -o tsv)

echo Creating Container if needed:
az storage container create -n $CONTAINER --account-name $SA --account-key $StorageAccountKey -o tsv

# Get SAS Token
SASKEY=$(az storage container generate-sas --account-name $SA --account-key $StorageAccountKey --name $CONTAINER --permissions rw --start $SASSTART --expiry $EXPIRY -o tsv)

# Create a read-list-only SAS token on the container and get the key
SASKEYRA=$(az storage container generate-sas --account-name $SA --account-key $StorageAccountKey --name $CONTAINER --permissions rl --start $SASSTART --expiry $EXPIRY -o tsv)

URL='https://'$SA'.blob.core.windows.net/'$CONTAINER'?'$SASKEY
#RAURL='https://'$SA'.blob.core.windows.net/'$CONTAINER'?'$SASKEYRA'&comp=list&restype=container'
echo Getting Logs from IoT-Hub: $HUB for device $DEVICE 

az iot hub invoke-module-method -n $HUB -d $DEVICE -m \$edgeAgent --mn UploadLogs --mp \
'
    {
        "schemaVersion": "1.0",
        "sasUrl": "'$URL'",
        "items": [
            {
                "id": "edge", 
                "filter": {
                    "tail": 10
                }
            },
            {
                "id": "publisher",
                "filter": {
                    "tail": 10
                }
            }
        ],
        "encoding": "none", 
        "contentType": "text"
    }
'
#echo Goto this URL to read: $RAURL
echo Use Azure Storage Explorer to view the contents of the storage account: $SA
