#!/bin/sh

apt update
apt dist-upgrade -y

mkdir -p /tmp/init

cat <<'EOF' > /tmp/init/traefik-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik-ingress-controller
  namespace: kube-system
---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: ingressroutes.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: IngressRoute
    plural: ingressroutes
    singular: ingressroute
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: middlewares.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: Middleware
    plural: middlewares
    singular: middleware
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: ingressroutetcps.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: IngressRouteTCP
    plural: ingressroutetcps
    singular: ingressroutetcp
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: ingressrouteudps.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: IngressRouteUDP
    plural: ingressrouteudps
    singular: ingressrouteudp
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: tlsoptions.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: TLSOption
    plural: tlsoptions
    singular: tlsoption
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: tlsstores.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: TLSStore
    plural: tlsstores
    singular: tlsstore
  scope: Namespaced

---
apiVersion: apiextensions.k8s.io/v1beta1
kind: CustomResourceDefinition
metadata:
  name: traefikservices.traefik.containo.us

spec:
  group: traefik.containo.us
  version: v1alpha1
  names:
    kind: TraefikService
    plural: traefikservices
    singular: traefikservice
  scope: Namespaced
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller

rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
      - networking.k8s.io
    resources:
      - ingresses
      - ingressclasses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses/status
    verbs:
      - update
  - apiGroups:
      - traefik.containo.us
    resources:
      - middlewares
      - ingressroutes
      - traefikservices
      - ingressroutetcps
      - ingressrouteudps
      - tlsoptions
      - tlsstores
    verbs:
      - get
      - list
      - watch

---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik-ingress-controller
subjects:
  - kind: ServiceAccount
    name: traefik-ingress-controller
    namespace: kube-system
EOF

cat <<'EOF' > /tmp/init/traefik.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: traefik
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: traefik
  template:
    metadata:
      labels:
        name: traefik
    spec:
      containers:
      - args:
        - --entryPoints.traefik.address=$(NODE_IP):9000
        - --entryPoints.web.address=$(NODE_IP):80
        - --entryPoints.websecure.address=$(NODE_IP):443
        - --entryPoints.websecure.http.tls=true
        - --api.dashboard=false
        - --ping=true
        - --providers.kubernetesingress
        - --providers.kubernetescrd
        image: traefik:2.3.5
        imagePullPolicy: IfNotPresent
        env:
          - name: NODE_IP
            valueFrom:
              fieldRef:
                fieldPath: status.hostIP
        name: traefik
        ports:
        - containerPort: 9000
          name: traefik
          protocol: TCP
        - containerPort: 80
          hostPort: 80
          name: web
          protocol: TCP
        - containerPort: 443
          hostPort: 443
          name: websecure
          protocol: TCP
        readinessProbe:
          failureThreshold: 1
          httpGet:
            path: /ping
            port: 9000
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 2
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /ping
            port: 9000
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 2
        securityContext:
          readOnlyRootFilesystem: true
          # https://github.com/kubernetes/kubernetes/issues/56374
          # Kubernetes cannot yet set ambiant capabilities.
          # So we run as root. Once this is fixed, run as 65532, runAsNonRoot: true
          runAsGroup: 0
          runAsNonRoot: false
          runAsUser: 0
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /data
          name: data
        - mountPath: /tmp
          name: tmp
      # dnsPolicy: ClusterFirst
      hostNetwork: true
      restartPolicy: Always
      # schedulerName: default-scheduler
      securityContext:
        fsGroup: 65532
      serviceAccount: traefik-ingress-controller
      serviceAccountName: traefik-ingress-controller
      terminationGracePeriodSeconds: 60
      volumes:
      - emptyDir: {}
        name: data
      - emptyDir: {}
        name: tmp
EOF


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
kubectl apply -f /tmp/init/traefik-account.yaml
kubectl apply -f /tmp/init/traefik.yaml
