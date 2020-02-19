if [ $# = 0 ]; then echo "No parameters found. Parameters = <tsi environment name>"; exit ; fi
export cloudShellID=$(az account show --query 'user.cloudShellID' -o tsv)
if [ -n "$cloudShellID" ]; then
    echo "Authenticated using CloudShell, for this script you must re-authenticate"
    az login
 else
    echo "Authenticated already." $cloudShellID
fi
DEVICE=$1
export tsienvironment=$(az resource show -g $DEVICE -n $DEVICE --resource-type Microsoft.TimeSeriesInsights/environments --query properties.dataAccessId -o tsv)

# Get Instances
export tsimodel=$(az rest --method get --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --query instances)
#tsimodel=$(cat "test.txt")

# Generate Updated Instances
export tsiinstances=$'{ "put":'$tsimodel'}'
export sample=$tsimodel
echo > test.txt

for row in $(echo "${sample}" | jq -r '.[] | @base64'); do
    _jq() { 
    	echo ${row} | base64 --decode | jq -r ${1} 
    }
    if [ $(_jq '.timeSeriesId[1]') = 'null' ]; then
        export description=$'DateTime'
        export instanceFi1=$'simulator'; export instanceFi2=$'DateTime'
    elif [ $(_jq '.timeSeriesId[1]') = 'Expression' ]; then
        export description=$'custom mathematical expression'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    elif [ $(_jq '.timeSeriesId[1]') = 'Random' ]; then
        export description=$'random number'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    elif [ $(_jq '.timeSeriesId[1]') = 'Square' ]; then
        export description=$'non-sinusoidal periodic waveform in which the amplitude alternates at a steady frequency between fixed minimum and maximum'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    elif [ $(_jq '.timeSeriesId[1]') = 'Sawtooth' ]; then
        export description=$'a kind of non-sinusoidal waveform'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    elif [ $(_jq '.timeSeriesId[1]') = 'Counter' ]; then
        export description=$'a count from 0 to 100'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    elif [ $(_jq '.timeSeriesId[1]') = 'Sinusoid' ]; then
        export description=$'a curve having the form of a sine wave'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    elif [ $(_jq '.timeSeriesId[1]') = 'Triangle' ]; then
        export description=$'non-sinusoidal waveform named for its triangular shape. It is a periodic, piecewise linear, continuous real function'
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    else
        export description=$''
        export temp=$(_jq '.timeSeriesId[1]'); export instanceFi1=$'simulator'; export instanceFi2=${temp:0:3}
    fi
    echo $(_jq .) | jq --arg description "$description" --arg instanceFi1 "$instanceFi1" --arg instanceFi2 "$instanceFi2" '{ timeSeriesId: .timeSeriesId, hierarchyIds: .hierarchyIds, name: .timeSeriesId[1], description: $description, instanceFields: { system: $instanceFi1, unit: $instanceFi2} }' >>test.txt
    echo ',' >>test.txt
done

# Fix JSON
sed '$ s/.$//' test.txt > test.tmp && sed -e 1's/.*/[ &/' test.tmp > test2.tmp && echo ']' >>test2.tmp && cat test2.tmp | jq '.' > test.txt && rm test.tmp && rm test2.tmp
tsiinstances2=$(cat test.txt)
tsiinstances=$'{ "put":'$tsiinstances2' }'

# Post Updated Instances
az rest --method post --uri https://$tsienvironment.env.timeseries.azure.com/timeseries/instances/'$batch'?api-version=2018-11-01-preview --resource https://api.timeseries.azure.com/ --body "$tsiinstances"
