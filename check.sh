#!/usr/bin/env bash

ACCESS_TOKEN=$(echo "$REQUEST_BODY" | jq -r ".access_token")
PUBLIC_KEY=$(echo "$REQUEST_BODY" | jq -r ".public_key")

if [ "$ACCESS_TOKEN" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 400'
    echo ''
    echo 'access token missing'
    exit 0
fi

if [ "$PUBLIC_KEY" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 400'
    echo ''
    echo 'public key missing'
    exit 0
fi

USERNAME=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://graph.microsoft.com/v1.0/me" | jq -r ".displayName")
if [ "$USERNAME" == "null" ]
then
    echo 'status: 401'
    echo 'content-type: text/plain'
    echo 'cache-control: no-store'
    echo ''
    echo 'not authorized'
    exit 0
fi

if [[ $(wg show wg0 dump | grep $PUBLIC_KEY | wc -l) -ne 0 ]]
then
    echo 'status: 200'
    echo 'content-type: text/plain'
    echo 'cache-control: no-store'
    echo ''
    echo 'OK'
else
    echo 'status: 404'
    echo 'content-type: text/plain'
    echo 'cache-control: no-store'
    echo ''
    echo 'not found'
fi

