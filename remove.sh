#!/usr/bin/env bash

ACCESS_TOKEN=$(echo "$REQUEST_BODY" | jq -r ".access_token")
PUBLIC_KEY=$(echo "$REQUEST_BODY" | jq -r ".public_key")

if [ "$ACCESS_TOKEN" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 400'
    echo ''
    echo '{"message":"access token missing"}'
    exit 0
fi

if [ "$PUBLIC_KEY" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 400'
    echo ''
    echo '{"message":"public key missing"}'
    exit 0
fi

USERNAME=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://graph.microsoft.com/v1.0/me" | jq -r ".displayName")
if [ "$USERNAME" == "null" ]
then
    echo 'status: 401'
    echo 'content-type: text/plain'
    echo 'cache-control: no-store'
    echo ''
    echo '{"message":"not authorized"}'
    exit 0
fi

PEER_REMOVE_RESULT=$(wg set wg0 peer $PUBLIC_KEY remove)
if [ $? -ne 0 ]
then
    echo 'status: 500'
    echo ''
    jq -n --arg details "$PEER_REMOVE_RESULT" '{"message": "unable to remove peer", "details": $details}'
else
    echo 'status: 200'
    echo ''
    echo '{"message":"ok"}'
fi
