#!/usr/bin/env bash

USERNAME=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://graph.microsoft.com/v1.0/me" | jq -r ".displayName")
if [ "$USERNAME" == "null" ]
then

    echo 'status: 401'
    echo 'content-type: text/html'
    echo 'cache-control: no-store'
    echo ''
    echo '<h3>WireGuard</h3>'
    echo '<p>Not authorized</p>'

else

    echo 'content-type: text/html'
    echo 'cache-control: no-store'
    echo ''
    echo '<h3>WireGuard</h3>'
    echo "<p>Hello $USERNAME</p>"
    if [[ $(wg show wg0 peers | wc -l) -ne 0 ]]
    then
        echo '<table border="1" cellspacing="0" cellpadding="5">'
        echo '<thead>'
        echo '<tr>'
        echo '<th>mail</th>'
        echo '<th>public key</th>'
        echo '<th>preshared key</th>'
        echo '<th>endpoint</th>'
        echo '<th>allowed ip</th>'
        echo '<th>latest handshake</th>'
        echo '<th>transfer rx</th>'
        echo '<th>transfer tx</th>'
        echo '<th>persistent keepalive</th>'
        echo '<th></th>'
        echo '</tr>'
        echo '</thead>'
        echo '<tbody>'
        # wg show wg0 dump | sed 1d | awk '{ print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td><td>"$6"</td><td>"$7"</td><td>"$8"</td><td><form style=\"margin:0\" action=/remove/"$1"><input type=submit value=&times; /></form></td></tr>" }'
        while IFS= read -r line; do
            peer=$(echo $line | awk '{ print $1 }')
            mail=$(cat "/tmp/wg/$peer/mail")
            echo '<tr>'
            echo "<td>$mail</td>"
            echo $line | awk -v access_token=$ACCESS_TOKEN '{ print "<td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td><td>"$6"</td><td>"$7"</td><td>"$8"</td>" }'
            echo "<td><button onclick=\"remove('$peer')\">&times;</button></td></td>"
            echo '</tr>'
        done <<< $(wg show wg0 dump | sed 1d)
        echo '</tbody>'
        echo '</table>'
        echo '<script>
            async function remove(public_key) {
                const access_token = new URL(window.location).searchParams.get("access_token")
                const response = await fetch("/remove", {
                    method: "POST",
                    body: JSON.stringify({ access_token, public_key })
                })
                const {message} = await response.json()
                alert(message)
                location.reload()
            }
        </script>'
    else
        echo '<p>At moment no peers configured</p>'
    fi

fi
