#!/usr/bin/env bash

ACCESS_TOKEN=$(echo "$REQUEST_BODY" | jq -r ".access_token")
PUBLIC_KEY=$(echo "$REQUEST_BODY" | jq -r ".public_key")

if [ "$ACCESS_TOKEN" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 400'
    echo ''
    echo '{"error":"access_token missing"}'
    exit 0
fi

if [ "$PUBLIC_KEY" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 400'
    echo ''
    echo '{"error":"public_key missing"}'
    exit 0
fi

# ACCESS_TOKEN=$(az account get-access-token --resource-type ms-graph | jq -r ".accessToken")

MAIL=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://graph.microsoft.com/v1.0/me" | jq -r ".mail" | tr '[:upper:]' '[:lower:]')
if [ "$MAIL" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 401'
    echo ''
    echo '{"error":"unauthorized"}'
    exit 0
fi

URLENCODED_GROUP_NAME=$(echo -n $ALLOWED_AD_GROUP_NAME | jq -sRr @uri)
FOUND=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" -H "ConsistencyLevel: eventual" "https://graph.microsoft.com/v1.0/me/memberOf?\$count=true&\$select=displayName,id&\$search=\"displayName:$URLENCODED_GROUP_NAME\"" | jq '.["@odata.count"]')
if [ "$FOUND" == "null" ]
then
    echo 'content-type: application/json'
    echo 'status: 403'
    echo ''
    echo '{"error":"forbidden"}'
    exit 0
fi

CLIENT_PRIVATE_IP=$(comm -13 <(
  wg show wg0 allowed-ips | awk '{ split($2, a, "/"); print a[1] }'
) <(
  nmap -sL -n $CIDR | awk '/Nmap scan report/{print $NF}' | tail -n +3 | sed \$d
) | head -n 1)

if [ -z "$CLIENT_PRIVATE_IP" ]
then
    echo 'content-type: application/json'
    echo 'status: 500'
    echo ''
    echo '{"error":"can not determine private ip for client"}'
    exit 0
fi


CONFIGURE_PEER_RESULT=$(wg set wg0 peer $PUBLIC_KEY allowed-ips "$CLIENT_PRIVATE_IP/32")

if [ $? -ne 0 ]
then
    echo 'content-type: application/json'
    echo 'status: 500'
    echo ''
    jq -n --arg details "$CONFIGURE_PEER_RESULT" '{"message": "unable to add peer", "details": $details}'
    exit 0
fi

mkdir -p "/tmp/wg/$PUBLIC_KEY/"
echo -n $MAIL > "/tmp/wg/$PUBLIC_KEY/mail"
echo -n $(date +%s) > "/tmp/wg/$PUBLIC_KEY/created"

echo 'content-type: application/json'
echo 'status: 200'
echo ''
echo "{\"client_private_ip\":\"$CLIENT_PRIVATE_IP\",\"server_public_key\":\"$(cat /etc/wireguard/server.publickey)\"}"
