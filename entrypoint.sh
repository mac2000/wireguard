#!/bin/sh

# common
# ------

# install wanted tools
apk add -q openssl jq fcgiwrap spawn-fcgi iptables wireguard-tools nmap netcat-openbsd bash vim

# spawn fastcgi
/usr/bin/spawn-fcgi -s /var/run/fcgiwrap.socket -M 766 /usr/bin/fcgiwrap

# determine server ip from given cidr
SERVER_IP=$(nmap -sL -n $CIDR | awk '/Nmap scan report/{print $NF}' | head -n 2 | tail -n 1)
echo "server_ip: $SERVER_IP"


# wireguard
# ---------

# create and configure wg0 interface
ip link add wg0 type wireguard
ip -4 address add $SERVER_IP dev wg0
ip link set mtu 1420 up dev wg0
ip -4 route add $CIDR dev wg0

# allow incomming and outgoing traffic, enable nat
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# generate server keys and configure wg0 interface
wg genkey | tee /etc/wireguard/server.privatekey | wg pubkey > /etc/wireguard/server.publickey
wg set wg0 listen-port 51820 private-key /etc/wireguard/server.privatekey
