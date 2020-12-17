# Simple way to deploy k3s

k3s is easy to deploy. However, by default the traefik load balancer doesn't have access to the source IP address. Also the network policy built into k3s is a bit limited.

To get the source IP address traefik must bind to the host IP address.

Also drop in cilium for more advanced network policies. It also allows reporting dropped network actions.

---

For VMs that can run init scripts, you can run boot.sh. Which runs the following:

```
# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable=traefik --disable-network-policy' sh -

# Install Cilium

# https://get.helm.sh/helm-v3.4.1-linux-amd64.tar.gz
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add cilium https://helm.cilium.io/
# helm show values cilium/cilium 

kubectl create -n kube-system secret generic cilium-ipsec-keys --from-literal=keys="3 rfc4106(gcm(aes)) $(echo $(dd if=/dev/urandom count=20 bs=1 2> /dev/null| xxd -p -c 64)) 128"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm install cilium cilium/cilium --version 1.9.1 \
  --namespace kube-system \
  --set encryption.enabled=true \
  --set encryption.nodeEncryption=true \
  --set enable-local-node-route=false \
  --set enable-ipv4=true

# Setup Traefik (with host ports to get source IP).
kubectl apply -f traefik-account.yaml
kubectl apply -f traefik.yaml
```

A simple way to block traffic and see reports.

```
# (example/NOT PROD) Apply example blocking policy for egress/ingress.
kubectl apply -f example-block.yaml

# Watch for dropped packets (fill in cilium-random from "kubectl get -A pods").
kubectl exec -it -n kube-system cilium-random -- cilium monitor -t drop
```

