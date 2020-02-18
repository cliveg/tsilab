if [ $# = 0 ]; then echo "No parameters found. Parameters = <tsi environment name>"; exit ; fi

export cloudShellID=$(az account show --query 'user.cloudShellID' -o tsv)
if [ -n "$cloudShellID" ]; then
    echo "Authenticated using CloudShell, for this script you must re-authenticate"
    az login
 else
    echo "Authenticated already." $cloudShellID
fi

# az account set --subscription 'if needed'

DEVICE=$1
export tsienvironment=$(az resource show -g $DEVICE -n $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments --query properties.dataAccessId -o tsv)

# Get Instances
export tsimodel=$(az rest --method get --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --query instances)

# Generate Updated Instances
export tsiinstances=$'{ "put":'$tsimodel'}'
export sample=$tsimodel
echo > test.txt

for row in $(echo "${sample}" | jq -r '.[] | @base64'); do
    _jq() { 
	echo ${row} | base64 --decode | jq -r ${1} 
    }
    echo  $(_jq .) | jq '{ timeSeriesId: .timeSeriesId, hierarchyIds: .hierarchyIds, name: .timeSeriesId[1], instanceFields: .instanceFields }' >>test.txt
    echo ',' >>test.txt
done

# Fix JSON
sed '$ s/.$//' test.txt > test.tmp && sed -e 1's/.*/[ &/' test.tmp > test2.tmp && echo ']' >>test2.tmp && cat test2.tmp | jq '.' > test.txt && rm test.tmp && rm test2.tmp
tsiinstances2=$(cat test.txt)
tsiinstances=$'{ "put":'$tsiinstances2' }'

# Post Updated Instances
echo $tsiinstances
az rest --method post --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances/'$batch'?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --body "$tsiinstances"

