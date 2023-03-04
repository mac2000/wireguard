#!/usr/bin/env bash

echo 'status: 200'
echo 'content-type: text/plain'
echo ''

if [[ $(wg show wg0 peers | wc -l) -ne 0 ]]
then
    echo '# HELP wireguard_sent_bytes_total Bytes sent to the peer'
    echo '# TYPE wireguard_sent_bytes_total counter'
    while IFS= read -r line; do
        peer=$(echo $line | awk '{ print $1 }')
        value=$(echo $line | awk '{ print $7 }')
        echo "wireguard_sent_bytes_total{public_key=\"$peer\"} $value"
    done <<< $(wg show wg0 dump | sed 1d)

    echo ''

    echo '# HELP wireguard_received_bytes_total Bytes received from the peer'
    echo '# TYPE wireguard_received_bytes_total counter'
    while IFS= read -r line; do
        peer=$(echo $line | awk '{ print $1 }')
        value=$(echo $line | awk '{ print $6 }')
        echo "wireguard_received_bytes_total{public_key=\"$peer\"} $value"
    done <<< $(wg show wg0 dump | sed 1d)

    echo ''

    echo '# HELP wireguard_latest_handshake_seconds Seconds from the last handshake'
    echo '# TYPE wireguard_latest_handshake_seconds counter'
    while IFS= read -r line; do
        peer=$(echo $line | awk '{ print $1 }')
        value=$(echo $line | awk '{ print $5 }')
        echo "wireguard_latest_handshake_seconds{public_key=\"$peer\"} $value"
    done <<< $(wg show wg0 dump | sed 1d)

fi
