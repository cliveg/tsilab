if [ $# = 0 ]; then echo "No parameters found. Parameters = <tsi environment name> <tsi hierarchy id> (optional - will create sample if one doesnt exist)"; exit ; fi

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

# If Hierarchy parameter supplied verify it is correct, else use an existing hierarchy, or create a sample one
if [ $# = 2 ]; then 
    export tsiHierarchyList=$(az rest --method get --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/hierarchies/?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --query hierarchies[].id -o tsv )
    if [[ "$tsiHierarchyList" == *"$2"* ]]; then echo "Hierarchy Exists: $2" ; tsiHierarchy=$2 ; else echo "Hierarchy Does Not Exist - please check and try again: $2" ; exit ; fi
else export tsiHierarchy=$(az rest --method get --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/hierarchies/?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --query hierarchies[0].id -o tsv )
fi

# Get Hierarchy
if [ -z "$tsiHierarchy" ]; then 
    echo "No Hierarchy Exists, Creating a sample."; 
    tsiHierarchy=$(az rest --method post --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/hierarchies/'$batch'?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --body '{"put":[{"name":"Location","source":{"instanceFieldNames":["iothub-connection-device-id","tagid"]}}]}' --query put[0].hierarchy.id -o tsv)
    if [ -z "$tsiHierarchy" ]; then "Error."; exit ; else echo $tsiHierarchy ; fi
else echo "A Hierarchy Exists"; fi

# Get Only New Instances to Process
searchstring='{"searchString":"","path":null,"instances":{"recursive":false,"sort":{"by":"DisplayName"},"highlights":true,"pageSize":100}}'
export hitCount=$(az rest --method post --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances/search?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --body $searchstring  --query instances.hitCount)

hitCount=$(($hitCount + 0))
if [[ $hitCount = 0 ]]; then echo $hitCount New Instances to Process; exit ; fi

echo Processing $hitCount New Instances
export tsimodel=$(az rest --method post --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances/search?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --body $searchstring --query instances.hits)

# Generate Updated Instances
export tsiinstances=$'{ "put":'$tsimodel'}'
export sample=$tsimodel
echo > test.txt

for row in $(echo "${sample}" | jq -r '.[] | @base64'); do
    _jq() { 
	echo ${row} | base64 --decode | jq -r ${1} 
    }
    echo  $(_jq .) | jq --arg csv $tsiHierarchy '{ timeSeriesId: .timeSeriesId, hierarchyIds: [$csv], name: .timeSeriesId[1], instanceFields: .instanceFields }' >>test.txt
    echo ',' >>test.txt
done

# Fix JSON
sed '$ s/.$//' test.txt > test.tmp && sed -e 1's/.*/[ &/' test.tmp > test2.tmp && echo ']' >>test2.tmp && cat test2.tmp | jq '.' > test.txt && rm test.tmp && rm test2.tmp
tsiinstances2=$(cat test.txt)
tsiinstances=$'{ "put":'$tsiinstances2' }'

# Post Updated Instances
echo 
echo Post Updated Instances:
echo $tsiinstances
az rest --method post --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances/'$batch'?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --body "$tsiinstances"
