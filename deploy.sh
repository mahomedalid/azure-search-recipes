#!/bin/bash

API_KEY="$1"
AZURE_SEARCH_RESOURCE="$2"
ENVIRONMENT="$3"
COLOR="$4"
PATCH_FILE=$ENVIRONMENT.patch
SUBSCRIPTION="my-azure-subscription"
VAULT_NAME="my-keyvault-name"
SECRET_NAME="MySearchIndexDeployPatch$ENVIRONMENT"

usage ()
{
  echo 'Usage: deploy.sh <apikey> <azure_search_resource> <environment> [instance]'
  echo ' '
  echo '     Examples: '
  echo '         $ deploy.sh ABCDABCD12341234 my-search prod blue'
  echo '         $ deploy.sh ABCDABCD12341234 my-search-staging staging green'
  exit
}

if [ "$#" -lt 3 ]
then
  usage
fi

if [ -z "$3" ]; then
  COLOR="green"
fi

AZ_RESOURCE_SUFFIX=""

if [ "$COLOR" = "green" ]; then
  AZ_RESOURCE_SUFFIX=""
else
  AZ_RESOURCE_SUFFIX=$COLOR
fi

if test -f "$PATCH_FILE"; then
   echo "$PATCH_FILE exist"
else
   echo "Downloading $PATCH_FILE"
   az login
   az keyvault secret download --file $PATCH_FILE --name $SECRET_NAME --vault-name $VAULT_NAME --subscription $SUBSCRIPTION
fi

git apply $PATCH_FILE

for i in index.*.json
do
  echo "Processing index $i ..."
  ORIGINAL_INDEX_NAME=`jq .name $i`
  TARGET_INDEX_NAME="${ORIGINAL_INDEX_NAME}${AZ_RESOURCE_SUFFIX}"
  echo "- Index name: $ORIGINAL_INDEX_NAME"
  jq ".name=.name+\"${AZ_RESOURCE_SUFFIX}\"" $i > "$i.${COLOR}"
done

for i in indexer.*.json
do
  echo "Processing indexer $i ..."
  ORIGINAL_INDEXER_NAME=`jq .name $i`
  TARGET_INDEXER_NAME="${ORIGINAL_INDEX_NAME}${AZ_RESOURCE_SUFFIX}"
  echo "- Indexer name: $ORIGINAL_INDEXER_NAME"
  jq ".name=.name+\"${AZ_RESOURCE_SUFFIX}\" | .targetIndexName=.targetIndexName+\"${AZ_RESOURCE_SUFFIX}\""  $i > "$i.${COLOR}"
done

BASE_URL="${BASE_URL}"

echo "\nDatasources ..."

for i in datasource.*.json
do
  DATASOURCE_NAME=`jq -r '.name' $i`
  echo "Deleting $DATASOURCE_NAME ..."
  curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -X DELETE "${BASE_URL}/datasources/${DATASOURCE_NAME}?api-version=2016-09-01"
  echo "Creating $DATASOURCE_NAME ..."
  curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -d "@$i" -X POST "${BASE_URL}/datasources?api-version=2016-09-01"
done

echo "\nUpdating Skillsets ..."

for i in skillset.*.json
do
  SKILLSET_NAME=`jq -r '.name' $i`
  echo "Deleting $DATASOURCE_NAME ..."
  curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -X DELETE "${BASE_URL}/skillsets/${SKILLSET_NAME}?api-version=2019-05-06"
  echo "Creating $DATASOURCE_NAME ..."
  curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -d "@$i" -X POST "${BASE_URL}/skillsets?api-version=2019-05-06"
done

echo "\nDeleting index and indexers..."

for i in index.*.json.$COLOR
do
    CURRENT_INDEX_NAME=`jq -r '.name' $i`
    echo "\nDeleting index ${CURRENT_INDEX_NAME} ..."
    curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -X DELETE "${BASE_URL}/indexes/${CURRENT_INDEX_NAME}?api-version=2019-05-06" --fail --silent --show-error
    echo "\nCreating index ${CURRENT_INDEX_NAME} ..." 
    curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -d "@$i" -X POST "${BASE_URL}/indexes?api-version=2019-05-06" --fail --silent --show-error 
done

for i in indexer.*.json.$COLOR
do
    CURRENT_INDEXER_NAME=`jq -r '.name' $i`
    echo "\nDeleting indexer ${CURRENT_INDEXER_NAME} ..."
    curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -X DELETE "${BASE_URL}/indexers/${CURRENT_INDEXER_NAME}?api-version=2019-05-06" --fail --silent --show-error
    echo "\nCreating indexer ${CURRENT_INDEXER_NAME} ..." 
    curl --header "Content-Type: application/json" --header "api-key: ${API_KEY}" -d "@$i" -X POST "${BASE_URL}/indexers?api-version=2019-05-06" --fail --silent --show-error 
done

echo "\nthe end.\n"
rm *.json.$COLOR
git apply -R $ENVIRONMENT.patch