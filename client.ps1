if (-not $args[0] -or $args[0] -notin @("start", "stop", "status")) {
  Write-Host "WireGuard VPN Client"
  Write-Host "Commands: start, stop, status"
  Write-Host "Config is saved here: ~/.config/vpn.conf"
  return
}

if (-not (Get-Command az -ErrorAction SilentlyContinue))
{
  Write-Host "az not found: choco install azure-cli"
  return
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue))
{
  Write-Host "kubectl not found: choco install kubernetes-cli"
  return
}

if (-not (Get-Command wireguard -ErrorAction SilentlyContinue))
{
  Write-Host "wireguard not found: choco install wireguard"
  return
}


if ($args[0] -eq "start") {
  $SERVER_PUBLIC_IP=(kubectl -n vpn get svc vpn -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
  $ACCESS_TOKEN=(az account get-access-token --resource-type ms-graph --query accessToken --output tsv)
  $CLIENT_PRIVATE_KEY=(wg genkey)
  $CLIENT_PUBLIC_KEY=(echo -n $CLIENT_PRIVATE_KEY | wg pubkey)
  $RESPONSE=(Invoke-RestMethod -Method Post -Uri "http://$SERVER_PUBLIC_IP/add" -Body (@{ public_key=$CLIENT_PUBLIC_KEY; access_token=$ACCESS_TOKEN } | ConvertTo-Json))
  $CLIENT_PRIVATE_IP=$RESPONSE.client_private_ip
  $SERVER_PUBLIC_KEY=$RESPONSE.server_public_key
  $DNS=(kubectl -n kube-system get svc kube-dns -o jsonpath="{.spec.clusterIP}") + ", " + (((kubectl get ns -o json | ConvertFrom-Json | Select-Object -ExpandProperty items | Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name) -join ".svc.cluster.local, ") + ".svc.cluster.local, svc.cluster.local, cluster.local")
  $ALLOWEDIPS=("10.0.0.0/8, " + ((kubectl get ing -A -o json | ConvertFrom-Json | Select-Object -ExpandProperty items | Select-Object -ExpandProperty status | Select-Object -ExpandProperty loadBalancer | Select-Object -ExpandProperty ingress | Select-Object -ExpandProperty ip -Unique) -join "/32, ") + "/32")

  New-Item ~/.config -ItemType Directory -ErrorAction SilentlyContinue
  $CONFIG=(Resolve-Path ~/.config/vpn.conf).Path
  Set-Content -Path $CONFIG -Encoding ascii -Value @"
[Interface]
Address = $CLIENT_PRIVATE_IP
PrivateKey = $CLIENT_PRIVATE_KEY
DNS = $DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $($SERVER_PUBLIC_IP):51820
AllowedIPs = $ALLOWEDIPS
PersistentKeepalive = 25
"@

  wireguard /installtunnelservice $CONFIG
  Write-Host "started"
  return
}

if ($args[0] -eq "stop") {
  wireguard /uninstalltunnelservice vpn
  Write-Host "stopped"
  return
}

if ($args[0] -eq "status") {
  wg
  return
}
