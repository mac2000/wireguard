#!/usr/bin/env bash

echo 'status: 200'
echo 'content-type: text/event-stream'
echo 'cache-control: no-store'
echo 'transfer-encoding: chunked'
echo ''
if [[ $(wg show wg0 peers | wc -l) -ne 0 ]]
then
    while IFS= read -r line; do
        peer=$(echo $line | awk '{ print $1 }')
        echo "peer: $peer"
        created=$(cat "/tmp/wg/$peer/created")
        echo "created: $created"
        handshake=$(echo $line | awk '{ print $5 }')
        echo "handshake: $handshake"
        now=$(date +%s)
        seconds_since_handshake=$(echo "$(($now-$handshake))")
        echo "seconds_since_handshake: $seconds_since_handshake"
        if [ "$seconds_since_handshake" -gt "3600" ]
        then
            seconds_since_created=$(echo "$(($now-$created))")
            echo "seconds_since_created: $seconds_since_created"
            if [ "$seconds_since_created" -gt "3600" ]
            then
                wg set wg0 peer $peer remove
                echo 'action: removed'
            else
                echo 'action: skipped, just created'
            fi
        else
            echo 'action: skipped, was active'
        fi
        echo ''
    done <<< $(wg show wg0 dump | sed 1d)
else
    echo 'nothing to do'
fi
