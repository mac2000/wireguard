# WireGuard, Azure, Kubernetes, Active Directory

Goal: passwordless WireGuard VPN running inside Azure AKS Kubernetes cluster with ephemeral secrets and clients connecting via Azure Active Directory

<details>
<summary>How does WireGuard works?</summary>

In short WireGuard is build into the kernel and just works out of the box so there is no need to do something special about it. [Here](https://mac-blog.org.ua/kubernetes-wireguard/) you may found few examples of how you can get it up and running, but in simplest case it will be as easy as:

```bash
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: demo
  labels:
    app: demo
spec:
  nodeSelector:
    kubernetes.io/os: linux
  containers:
    - name: demo
      image: nginx:alpine
      securityContext:
        capabilities:
          add:
            - NET_ADMIN
---
apiVersion: v1
kind: Service
metadata:
  name: demo
spec:
  type: LoadBalancer
  selector:
    app: demo
  ports:
    - name: http
      port: 80
      protocol: TCP
    - name: wireguard
      port: 51820
      protocol: UDP
EOF
```

Note: we have started nginx alpine image, it does not have anything related to WireGuard but it will still work because it is build into the kernel, the only real difference is that we need an `NET_ADMIN` capability, otherwise we wont be allowed to create an netrowk interface

Here is the basic setup for "server side":

```bash
# jump into container
kubectl exec -it demo -- sh

# we are creating wireguard interface and we did not setup anything yet
ip link add wg0 type wireguard
ip -4 address add 10.13.13.1 dev wg0
ip link set mtu 1420 up dev wg0
ip -4 route add 10.13.13.0/24 dev wg0

# concrete in this example we missing iptables utility
apk add iptables

# allow incomming and outgoing traffic, enable nat
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# the same way as with iptables, there is an wireguard utilities
apk add wireguard-tools

# generate server keys and configure wg0 interface
wg genkey | tee /etc/wireguard/server.privatekey | wg pubkey > /etc/wireguard/server.publickey
wg set wg0 listen-port 51820 private-key /etc/wireguard/server.privatekey

# at this step, the command below will print configured wg0 interface, which means we are ready to accept connections
wg

# now we may prepare config file for very first client
wg genkey | tee /etc/wireguard/peer1.privatekey | wg pubkey > /etc/wireguard/peer1.publickey

wg set wg0 peer "$(cat /etc/wireguard/peer1.publickey)" allowed-ips 10.13.13.2/32

# check (should show not only wg0, but added peer as well)
wg

# dump the config
tee /etc/wireguard/peer1.conf > /dev/null <<EOT
[Interface]
# client private ip
Address = 10.14.14.2
# client private key
PrivateKey = $(cat /etc/wireguard/peer1.privatekey)
# dns and search domains
DNS = 10.0.0.10, default.svc.cluster.local, svc.cluster.local, cluster.local

[Peer]
# server public key
PublicKey = $(cat /etc/wireguard/server.publickey)
# server public ip and port
Endpoint = TODO_REPLACE_ME_WITH_PUBLIC_IP:51820
# ip addresses that should be routed via vpn
AllowedIPs = 10.0.0.0/8
PersistentKeepalive = 25
EOT

# print config for a client
cat /etc/wireguard/peer1.conf
# remove sensitive files, no need to store them
rm /etc/wireguard/peer1.conf
rm /etc/wireguard/peer1.privatekey
```

And now we may import config to the WireGuard client and connect

But there are few catches:

- server should not know client private key
- we need to transfer it somehow to clients
- the addition of client is manual and tidious
- because of how this done we need to keep track of created configs and remove them in case of teammates leave the company
- ideally we may also want to rotate this keys from time to time

PS: do not forget to cleanup after your experiments by running: `kubectl delete po,svc demo`


</details>


<details>
<summary>How this project works?</summary>

My very first approach was to have some fun and implement both server and client in golang, you may found some starting points [here](https://mac-blog.org.ua/golang-wireguard-console-client/). But later I have realized that everything may be as simple as set of few bash scripts which is somewhat awesome, let's pretend we are doing everything "unix way"

So, I am pretending that the person who will need such vpn will have az cli, kubectl and wireguard tools installed already, aka: `brew install azure-cli kubectl wireguard-tools`

Also I am pretending that `az login` was called and user did authenticated with his Active Directory account, 2FA and whatever else is needed.

We pretend that `kubectl` is connected to target cluster and can talk to it

Now we may:

- `CLIENT_PRIVATE_KEY=$(wg genkey)` - create private key (note: no one will know it, it wont leave our machine)
- `CLIENT_PUBLIC_KEY=$(echo -n $CLIENT_PRIVATE_KEY | wg pubkey)` - create an public key that we will send to our server
- `ACCESS_TOKEN=$(az account get-access-token --resource-type ms-graph | jq -r ".accessToken")` - get an access token that we will also send to server so it can verify it and check if we have privileges

The next step will be to send our public key and access token to the server and it will:

- `curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://graph.microsoft.com/v1.0/me"` - check if this token is valid at all
- `wg set wg0 peer $PUBLIC_KEY allowed-ips "10.13.13.3/32"` - configure the peer
- respond to client with choosen ip and server public key

Notes:

- no one knowns client private key except him
- in response we are also sending only server public key
- with help of access token we may authenticate user
- if wanted we may authorize him by checking group membership


The server itself is the same nginx alpine image with custom entry point that is isntalling few tools and configures the interface and set of scripts to serve endpoints.

So we kind of achieving our goal here, because secrets are not shared and as a result there is nothing to hide or rotate.

</details>


<details>
<summary>How to setup the server</summary>

This repo is just an starting point example. There is no need to build some custom images, but you can if you want. Also you may want to build an API in your favorite language.

The setup of server itself is as simple as:

```bash
kubectl apply -k .
```

It will spin up:

- vpn namespace
- nginx deployment we have talked about in previous sections
- the service to expose our vpn to outside world
- cronjob that will remove outdated peers

</details>


## The client guide

Just downlad the client script and put it somewhere accessible in path, e.g.:

```bash
wget -O vpn https://raw.githubusercontent.com/mac2000/wireguard/main/client.sh
chmod +x vpn
sudo mv vpn /usr/local/bin/vpn
```

Then make sure you logged in `az login`

Switch to the Kubernetes cluster where you have server running `kubectl config use-context my-cluster-name`

And simply run `vpn start`

It will perform some basic checks and do everything for you, the output will be something like this:

```log
checking if kubectl is connected: ok
checking az cli: ok
retrieving server public ip: ok
retrieving access token: ok
generating client keys: ok
sending request: ok
retrieving dns addr: ok
preparing searchdomains: ok
preparing allowed ips: ok
preparing confing: ok
starting wireguard
[#] wireguard-go utun
[+] Interface for vpn is utun9
[#] wg setconf utun9 /dev/fd/63
[#] ifconfig utun9 inet 10.14.14.2 10.14.14.2 alias
[#] ifconfig utun9 up
[#] route -q -n add -inet 20.13.179.68/32 -interface utun9
[#] route -q -n add -inet 10.64.0.4/32 -interface utun9
[#] route -q -n add -inet 10.0.0.0/8 -interface utun9
[#] networksetup -getdnsservers Wi-Fi
[#] networksetup -getsearchdomains Wi-Fi
[#] networksetup -setdnsservers Wi-Fi 10.0.0.10
[#] networksetup -setsearchdomains Wi-Fi default.svc.cluster.local svc.cluster.local cluster.local
[+] Backgrounding route monitor
```

And you are connected, to check this you may want to run `vpn status` that will output:

```log
interface: utun9
  public key: idhqVIJel7hnZa5Cfl6mL02T8BewzVJwurFosPXAfGI=
  private key: (hidden)
  listening port: 56239

peer: jvUrYmfK8PhfksMfHKe76WVzRbtOeQtT4ZPUgU4eqDc=
  endpoint: 20.166.201.55:51820
  allowed ips: 10.0.0.0/8, 20.13.179.68/32, 10.64.0.4/32
  latest handshake: 2 minutes, 6 seconds ago
  transfer: 18.81 KiB received, 8.71 KiB sent
  persistent keepalive: every 25 seconds
retrieving client public key: ok
retrieving access token: ok
retrieving server public ip: ok
sending check request: OK
```

To disconnect run somethin like `vpn stop`

> Have a look at `client.sh` script for other options you have.

Whenever you connected following this should technically work:

```bash
# check if we can talk to kubernetes dns
nc -vz 10.0.0.10 53

# check if we can resolve
nslookup prometheus 10.0.0.10

# check if we can connect
curl -s -i http://prometheus/metrics | head -n 1
```

And suddenly we are inside the cluster, which means not only I can open [http://prometheus/](http://prometheus/) in my browser but as well the service I'm building can talk to its dependencies as if it was running inside the cluster.
