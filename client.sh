#!/usr/bin/env bash

if [ -z $(which kubectl) ]
then
    echo "kubectl not found: brew install kubectl"
    exit 1
fi


if [ -z $(which wg-quick) ]
then
    echo "wireguard tools not found: brew install wireguard-tools"
    exit 1
fi


if [ -z $(which az) ]
then
    echo "azure tools not found: brew install azure-cli"
    exit 1
fi


case $1 in

    up|start|connect)

        if [[ $(sudo wg | wc -l) -ne 0 ]]
        then
            echo "you already connected"
            exit 1
        fi

        echo -n "checking if kubectl is connected: "
        if ! kubectl get ns default >/dev/null 2>&1
        then
            echo "kubectl is not connected"
            exit 1
        else
            echo "ok"
        fi


        echo -n "checking az cli: "
        if ! az account show >/dev/null 2>&1
        then
            echo "az cli not connected, run: az login"
            exit 1
        else
            echo "ok"
        fi

        echo -n "retrieving server public ip: "
        SERVER_PUBLIC_IP=$(kubectl -n vpn get svc vpn -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        if [ -z "$SERVER_PUBLIC_IP" ]
        then
            echo "can not find vpn service public ip, make sure that kubernetes your are pointing right now has vpn being deployed and running"
            exit 1
        else
            echo "ok"
        fi

        echo -n "retrieving access token: "
        ACCESS_TOKEN=$(az account get-access-token --resource-type ms-graph | jq -r ".accessToken")
        if [ -z "$ACCESS_TOKEN" ]
        then
            echo "can not get access token for your account"
            echo "try to run the following command to see why it is not working:"
            echo "az account get-access-token --resource-type ms-graph"
            exit 1
        else
            echo "ok"
        fi

        echo -n "generating client keys: "
        CLIENT_PRIVATE_KEY=$(wg genkey)
        CLIENT_PUBLIC_KEY=$(echo -n $CLIENT_PRIVATE_KEY | wg pubkey)
        echo "ok"

        echo -n "sending request: "
        RESPONSE=$(curl -s -X POST "http://$SERVER_PUBLIC_IP/add" -d "{\"access_token\":\"$ACCESS_TOKEN\",\"public_key\":\"$CLIENT_PUBLIC_KEY\"}")
        CLIENT_PRIVATE_IP=$(echo $RESPONSE | jq -r ".client_private_ip")
        SERVER_PUBLIC_KEY=$(echo $RESPONSE | jq -r ".server_public_key")

        if [ "$CLIENT_PRIVATE_IP" == "null" ]
        then
            echo "was not able to retrieve an client private ip"
            echo "the response was:"
            echo $RESPONSE
            exit 1
        fi

        if [ "$SERVER_PUBLIC_KEY" == "null" ]
        then
            echo "was not able to retrieve an server public key"
            echo "the response was:"
            echo $RESPONSE
            exit 1
        fi
        echo "ok"

        echo -n "retrieving dns addr: "
        DNS=$(kubectl -n kube-system get svc kube-dns -o jsonpath="{.spec.clusterIP}")
        if [ -z "$DNS" ]
        then
            echo "was not able to retireve dns ip address"
            echo "i did tried to run following command to get it:"
            echo "kubectl -n kube-system get svc kube-dns"
            exit 1
        else
            echo "ok"
        fi

        echo -n "preparing searchdomains: "
        for NS in $(kubectl get ns -o jsonpath="{.items[*].metadata.name}")
        do
            DNS="$DNS, $NS.svc.cluster.local"
        done
        DNS="$DNS,  svc.cluster.local, cluster.local"
        echo "ok"

        echo -n "preparing allowed ips: "
        ALLOWEDIPS="10.0.0.0/8"
        for IP in $(kubectl get ing -A -o jsonpath="{.items[*].status.loadBalancer.ingress[0].ip}" | tr ' ' '\n' | uniq)
        do
            ALLOWEDIPS="$ALLOWEDIPS, $IP/32"
        done
        echo "ok"

        echo -n "preparing confing: "
        mkdir -p ~/.config

        echo "[Interface]" > ~/.config/vpn.conf
        echo "Address = $CLIENT_PRIVATE_IP" >> ~/.config/vpn.conf
        echo "PrivateKey = $CLIENT_PRIVATE_KEY" >> ~/.config/vpn.conf
        echo "DNS = $DNS" >> ~/.config/vpn.conf
        echo "" >> ~/.config/vpn.conf
        echo "[Peer]" >> ~/.config/vpn.conf
        echo "PublicKey = $SERVER_PUBLIC_KEY" >> ~/.config/vpn.conf
        echo "Endpoint = $SERVER_PUBLIC_IP:51820" >> ~/.config/vpn.conf
        echo "AllowedIPs = $ALLOWEDIPS" >> ~/.config/vpn.conf
        echo "PersistentKeepalive = 25" >> ~/.config/vpn.conf
        echo "" >> ~/.config/vpn.conf

        chmod 600 ~/.config/vpn.conf
        echo "ok"

        echo "starting wireguard"
        wg-quick up ~/.config/vpn.conf
    ;;

    status|check)
        if [[ $(sudo wg | wc -l) -ne 0 ]]
        then
            sudo wg

            echo ''

            echo -n "retrieving client public key: "
            CLIENT_PUBLIC_KEY=$(sudo wg | grep '  public key: ' | awk '{ print $3 }')
            echo "ok"

            echo -n "retrieving access token: "
            ACCESS_TOKEN=$(az account get-access-token --resource-type ms-graph | jq -r ".accessToken")
            echo "ok"

            echo -n "retrieving server public ip: "
            SERVER_PUBLIC_IP=$(kubectl -n vpn get svc vpn -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
            echo "ok"

            echo -n "sending check request: "
            curl -s -X POST "http://$SERVER_PUBLIC_IP/check" -d "{\"access_token\":\"$ACCESS_TOKEN\",\"public_key\":\"$CLIENT_PUBLIC_KEY\"}"
        else
            echo "disconnected"
        fi
    ;;

    down|stop|disconnect)
        wg-quick down ~/.config/vpn.conf
        echo '[#] rm -f ~/.config/vpn.conf'
        rm -f ~/.config/vpn.conf || true
    ;;

    ui|portal|manage)
        echo -n "checking if kubectl is connected: "
        if ! kubectl get ns default >/dev/null 2>&1
        then
            echo "kubectl is not connected"
            exit 1
        else
            echo "ok"
        fi


        echo -n "checking az cli: "
        if ! az account show >/dev/null 2>&1
        then
            echo "az cli not connected, run: az login"
            exit 1
        else
            echo "ok"
        fi

        echo -n "retrieving server public ip: "
        SERVER_PUBLIC_IP=$(kubectl -n vpn get svc vpn -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
        if [ -z "$SERVER_PUBLIC_IP" ]
        then
            echo "can not find vpn service public ip, make sure that kubernetes your are pointing right now has vpn being deployed and running"
            exit 1
        else
            echo "ok"
        fi

        echo -n "retrieving access token: "
        ACCESS_TOKEN=$(az account get-access-token --resource-type ms-graph | jq -r ".accessToken")
        if [ -z "$ACCESS_TOKEN" ]
        then
            echo "can not get access token for your account"
            echo "try to run the following command to see why it is not working:"
            echo "az account get-access-token --resource-type ms-graph"
            exit 1
        else
            echo "ok"
        fi

        open "http://$SERVER_PUBLIC_IP/?access_token=$ACCESS_TOKEN"
    ;;

    *)
        echo "WireGuard VPN Client"
        echo ""
        echo "Commands:"
        echo "  up      start vpn connection"
        echo "  down    stop vpn connection"
        echo "  status  current status"
        echo ""
        echo "Config is saved here: ~/.config/vpn.conf"
        echo ""
    ;;

esac
