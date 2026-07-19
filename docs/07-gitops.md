# GitOps — k3s + Flux

Architettura del cluster k3s e gestione GitOps con Flux CD v2.

## k3s su NixOS

`k3s` gira come **servizio host** sul NixOS baremetal (non in VM/container
separato). Configurazione in [`hosts/nebula/k3s.nix`](../hosts/nebula/k3s.nix).

### CNI: Flannel (bundled)

k3s usa **Flannel** come CNI di default (bundled, nessun bootstrap esterno).
La scelta precedente di Cilium è stata rimossa (vedi
[stack-decisions.md#d1](stack-decisions.md#d1--flannel-bundled-k3s)) perché il bootstrap
era fragile su NixOS (chicken-and-egg CNI, helm-diff plugin path non-standard,
servizio systemd custom). Su astra (single-node) Flannel è più che sufficiente.

Cilium può essere aggiunto via Flux HelmRelease in futuro quando il cluster è
stabile.

### Servizi disabilitati dal bundled k3s

```nix
services.k3s.extraFlags = toString [
  "--disable=traefik"              # Traefik via Flux (klipper-lb espone 80/443)
  "--disable=metrics-server"       # Beszel copre monitoring
  "--write-kubeconfig-mode=0644"   # kubeconfig leggibile da utente
];
```

| Servizio bundled | Stato | Note |
|------------------|-------|------|
| Flannel          | ✅ attivo | CNI di default k3s |
| Traefik bundled  | ❌ disabilitato | HelmRelease Flux (chart 41.x) |
| CoreDNS          | ✅ attivo + override | Custom ConfigMap → Technitium |
| kube-proxy       | ✅ attivo | Standard k3s |
| servicelb (klipper-lb) | ✅ attivo | Espone 80/443 sull'IP del nodo (192.168.178.2) → forwarda a Traefik 8000/8443. Service `traefik` type=LoadBalancer si appoggia qui. |
| local-storage    | ✅ attivo (default) | ZFS dataset `tank/volumes`, PVC usano `local-path` |
| metrics-server   | ❌ disabilitato | Beszel (esterno k3s) |

## Flux CD v2

Tutto il cluster è gestito da **Flux** in GitOps.

### Struttura

```
k8s/
├── clusters/dyson/                      ← Kustomization radice (5 file)
│   ├── cert-manager.yaml             → k8s/infra/cert-manager/install
│   ├── infrastructure.yaml           → k8s/infra/cert-manager/config (dependsOn cert-manager)
│   ├── traefik.yaml                  → k8s/infra/traefik/install
│   ├── traefik-config.yaml          → k8s/infra/traefik/config (dependsOn traefik)
│   └── apps.yaml                     → k8s/apps/ (dependsOn infrastructure)
│
├── infra/                             ← HelmRelease di infrastruttura (split install/config)
│   ├── cert-manager/
│   │   ├── install/                  → namespace + HelmRelease (controller layer)
│   │   └── config/                   → ClusterIssuer + Certificate + secret (depends on CRD)
│   └── traefik/
│       ├── install/                  → HelmRelease (controller layer)
│       └── config/                   → TLSStore (depends on traefik CRD)
│
└── apps/                              ← Servizi applicativi
    ├── beszel/                        → monitoring hub
    ├── homepage/                      → dashboard
    ├── infra-proxy/                   → reverse proxy per host fisici
    ├── technitium/                    → expose Technitium web UI via Traefik
    └── uptime-kuma/                   → status page
```

### Kustomization (5 Kustomization, ordine garantito da `dependsOn`)

Il pattern install/config separa l'install del controller (HelmRelease + CRD)
dalle risorse che dipendono dalle CRD. Flux garantisce l'ordine:

```
cert-manager (controller)  →  infrastructure (config cert-manager)
                                ↓
traefik (controller)        →  traefik-config (config traefik)
                                ↓
apps (tutto k8s/apps/, dependsOn infrastructure)
```

Esempio — [`k8s/clusters/dyson/cert-manager.yaml`](../k8s/clusters/dyson/cert-manager.yaml):

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager
  namespace: flux-system
spec:
  interval: 1m
  retryInterval: 5m
  timeout: 10m
  prune: true
  wait: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./k8s/infra/cert-manager/install
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: cert-manager
      namespace: cert-manager
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: clusterissuers.cert-manager.io
    - apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      name: certificates.cert-manager.io
```

[`k8s/clusters/dyson/infrastructure.yaml`](../k8s/clusters/dyson/infrastructure.yaml):
identica ma `path: ./k8s/infra/cert-manager/config` e
`dependsOn: [{ name: cert-manager }]`. Stesso pattern per `traefik` e
`traefik-config`. `apps.yaml` ha `path: ./k8s/apps` e
`dependsOn: [{ name: infrastructure }]`.

### Bootstrap (una tantum)

Se k3s è stato installato da NixOS con i secret già configurati, Flux
dovrebbe partire automaticamente al primo boot (i manifest `00-*` in
`/var/lib/rancher/k3s/server/manifests/` includono Secret GitRepository +
kustomize-controller).

Se per qualche motivo Flux non parte, bootstrap manuale dalla workstation:

```bash
# 1. Recupera kubeconfig
ssh cosimo@192.168.178.2 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config-nebula
# Modifica server: https://192.168.178.2:6443
sed -i 's/127.0.0.1/192.168.178.2/' ~/.kube/config-nebula

# 2. Installa Flux CLI (workstation)
nix-shell -p fluxcd

# 3. Bootstrap
flux bootstrap github \
  --owner=iltruma \
  --repository=astra \
  --branch=main \
  --path=k8s/clusters/dyson \
  --personal

# 4. Crea il secret sops-age (se non già fatto da k3s)
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-key.txt
```

## Aggiungere un nuovo servizio

```bash
# 1. Crea la cartella app
mkdir k8s/apps/myservice/
cd k8s/apps/myservice/

# 2. Crea i manifest + kustomization.yaml
cat > namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: myservice
EOF

cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myservice
  namespace: myservice
spec:
  replicas: 1
  selector:
    matchLabels: { app: myservice }
  template:
    metadata:
      labels: { app: myservice }
    spec:
      containers:
        - name: myservice
          image: myuser/myservice:latest
          ports: [{ containerPort: 8080 }]
EOF

cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: myservice
  namespace: myservice
spec:
  selector: { app: myservice }
  ports: [{ port: 80, targetPort: 8080 }]
EOF

cat > ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myservice
  namespace: myservice
  annotations:
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
    - hosts: [myservice.lab.paroparo.it]
      secretName: wildcard-lab-paroparo-it
  rules:
    - host: myservice.lab.paroparo.it
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myservice
                port:
                  number: 80
EOF

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
EOF

# 3. Aggiungi a k8s/apps/kustomization.yaml
cd ../..
echo "  - myservice" >> k8s/apps/kustomization.yaml

# 4. Commit + push
git add k8s/apps/myservice/ k8s/apps/kustomization.yaml
git commit -m "feat(k8s): add myservice"
git push
# Flux sincronizza entro 10 min (o forza con: flux reconcile kustomization apps)
```

## Comandi utili

```bash
# Stato Flux
flux get kustomizations
flux get helmreleases -A
flux get sources all

# Forza sync
flux reconcile kustomization apps --with-source
flux reconcile kustomization infrastructure --with-source

# Log
flux logs --all-namespaces --tail 50

# Stato k3s
k3s kubectl get nodes
k3s kubectl get pods -A
```

## Verifica

```bash
# Cluster up
k3s kubectl get nodes
# NAME      STATUS   ROLES                  AGE   VERSION
# nebula   Ready    control-plane,master   Xm    v1.30.x+k3s1

# Tutti i pod Running
k3s kubectl get pods -A
# (nessun pod in CrashLoopBackOff, Pending, o Error)

# Flux sincronizza
flux get kustomizations
# NAME            READY   STATUS
# infrastructure  True    Applied revision: main@sha1:...
# apps            True    Applied revision: main@sha1:...

# HelmRelease pronte
flux get helmreleases -A
# NAME           READY   STATUS
# cert-manager   True    ...
# traefik        True    ...
```

## Riferimenti

- [k3s NixOS module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/cluster/k3s/)
- [Flux CD v2](https://fluxcd.io/flux/)
- [k3s in pure Nix](https://discourse.nixos.org/t/k3s-clusters-and-deployments-in-pure-nix/61794)
