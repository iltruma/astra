# Secrets — SOPS + age

Tutti i segreti del repo sono cifrati con **SOPS + age**, sia per il cluster
k8s (Flux kustomize-controller) che per l'host NixOS (sops-nix). Stessa
chiave, stesso `.sops.yaml`, stessa CLI.

## Perché SOPS + age (e non Vault, Sealed Secrets, agenix)

| Caratteristica       | Vault           | Sealed Secrets | agenix          | **SOPS + age**        |
|----------------------|-----------------|----------------|-----------------|----------------------|
| Server esterno       | ✅ obbligatorio | ❌ (controller)| ❌              | ❌                   |
| Cluster dependency   | n/a             | ✅             | ❌              | ❌ (decifra al boot) |
| Reinstall cluster    | ✅              | ❌             | ✅              | ✅                   |
| Multi-host           | ✅              | n/a           | ✅ (per host)   | ✅ (stesso file)     |
| PR diff              | n/a             | ❌ base64      | ✅              | ✅ (chiavi visibili) |
| Toolchain            | pesante         | leggera        | minimalista     | **unificata**        |
| Tool segreto host    | ❌ (separato)   | ❌             | ✅              | ✅ (sops-nix)        |

**SOPS + age vince** perché:
- Un solo tool (`sops` CLI) per tutto (host + k8s)
- Un solo file config (`.sops.yaml`) per tutto
- Una sola chiave per tutto
- Diff leggibili (chiavi YAML in chiaro, valori cifrati)
- No server esterno, no controller in cluster

## Architettura

```
┌──────────────────────────────────────────────────────────┐
│                      Repo Git                            │
│  .sops.yaml (regole cifratura)                            │
│  secrets/*.enc.yaml          → sops-nix → host           │
│  k8s/**/*.enc.yaml          → Flux SOPS → k8s           │
└──────────────────────────────────────────────────────────┘
            │ cifrati con
            ▼
   ┌─────────────────┐
   │  Age key pair   │
   │  pub: age1...   │ ← in .sops.yaml
   │  priv: AGE-SEC  │ ← in /run/secrets/ (sops-nix)
   │                   ← in Secret k8s (Flux SOPS)
   └─────────────────┘
```

## File di config

### Bootstrap al primo install

sops-nix decifra i secret leggendo la chiave da `sops.age.keyFile`
(default `/etc/sops/age/keys.txt`, repo-specific `/persist/sops/age/keys.txt`).
Al primo install, `/persist` non esiste ancora, quindi la chiave va pushata sul
target durante l'install.

Il pattern è documentato in [00-nixos-installation.md §3.1](00-nixos-installation.md#31-prepara-la-chiave-age-per-extra-files):
si prepara una directory con la struttura del path di destinazione
(`<extra>/persist/sops/age/keys.txt`) e si passa a nixos-anywhere via
`--extra-files`, che la copia in `/mnt` (la root del sistema in costruzione)
prima dell'attivazione.

```bash
EXTRA=$(mktemp -d)
mkdir -p "$EXTRA/persist/sops/age"
cp ~/.config/sops/age/keys.txt "$EXTRA/persist/sops/age/keys.txt"
chmod 600 "$EXTRA/persist/sops/age/keys.txt"

nix run github:nix-community/nixos-anywhere -- \
  --flake .#nebula \
  --target-host root@192.168.178.2 \
  --build-on local \
  --extra-files "$EXTRA"
```

Dopo il primo switch, verifica che i secret siano stati decifrati:

```bash
ssh cosimo@192.168.178.2 'sudo ls /run/secrets/'
# Deve contenere: k3s/  beszel/  tailscale/  ...
```

> **Perché è obbligatorio**: senza la chiave in `/persist`, sops-nix non può
> decifrare nulla e l'attivazione di k3s/Flux/tailscale/beszel fallisce. Il
> `--extra-files` è il bootstrap standard riconosciuto da nixos-anywhere
> (vedi [docs ufficiali](https://nix-community.github.io/nixos-anywhere/howtos/secrets.html)).

### `.sops.yaml` (root del repo)

```yaml
creation_rules:
  # Secret Kubernetes (k8s/apps/*, k8s/infra/*)
  - path_regex: k8s/.*\.enc\.yaml$
    age: "<AGE_PUBLIC_KEY>"
    encrypted_regex: '^(data|stringData)$'

  # Secret host NixOS (secrets/)
  - path_regex: secrets/.*\.enc\.yaml$
    age: "<AGE_PUBLIC_KEY>"
    encrypted_regex: '^(stringData|data|[A-Z_]+)$'
```

`encrypted_regex` limita cosa cifrare: solo i campi con dati sensibili. Le
chiavi YAML restano in chiaro per diff leggibili.

### Chiave age

Generata una volta:
```bash
age-keygen -o age-key.txt
# Output:
# Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# (salva in .sops.yaml)
```

Backup della chiave privata (`age-key.txt`) **FONDAMENTALE**:
- Password manager (1Password, Bitwarden, KeePass)
- Copia offline su USB cifrata
- Carta in cassaforte (opzionale)

Senza la chiave privata, i secret sono **irrecuperabili**. Il backup rclone
NON include la chiave (sarebbe un disastro di sicurezza).

## Secret per host (`secrets/*.enc.yaml`)

Decifrati da **sops-nix** all'attivazione NixOS, montati in `/run/secrets/`
(tmpfs, mai su disco).

### File in `secrets/`

| File | Contenuto | Consumer |
|------|-----------|----------|
| `flux-git-auth.enc.yaml` | SSH key per Flux pull da GitHub | k3s (manifest `flux-secret-git-auth.yaml`) |
| `flux-sops-age.enc.yaml` | Chiave age privata per Flux SOPS | k3s (Secret `sops-age` in `flux-system`) |
| `rclone-env.enc.yaml` | Credenziali R2 per backup | systemd `rclone-backup` (env file, **in pausa**) |
| `beszel-agent-key.enc.yaml` | Enrollment key Beszel agent | servizio host `beszel-agent` |
| `tailscale-auth.enc.yaml` | Auth key Tailscale | servizio host `tailscaled` |
| `taiga-cloudflare-acme.enc.yaml` | API token Cloudflare per ACME DNS-01 | host `taiga` (Mainsail) |

### Configurazione in `hosts/nebula/k3s.nix`

```nix
sops.secrets = {
  "k3s/flux-git-auth" = {
    sopsFile = ../../secrets/flux-git-auth.enc.yaml;
    format = "yaml";
  };
  "k3s/flux-sops-age" = {
    sopsFile = ../../secrets/flux-sops-age.enc.yaml;
    format = "yaml";
  };
};
```

I secret sono montati in `/run/secrets/k3s/...` e symlinkati in
`/var/lib/rancher/k3s/server/manifests/flux-secret-*.yaml` via `systemd.tmpfiles.rules`
(il manifest `flux-namespace` che crea il namespace `flux-system` è applicato
direttamente dal modulo k3s, non via symlink).

### Configurazione in `hosts/nebula/backup.nix`

```nix
sops.secrets."backup/rclone-env" = {
  sopsFile = ../../secrets/rclone-env.enc.yaml;
  format = "yaml";
};
```

Montato in `/run/secrets/backup/rclone-env` e consumato da systemd
`rclone-backup.service` via `EnvironmentFile = ...path`.

## Secret per k8s (`k8s/**/*.enc.yaml`)

Decifrati da **Flux kustomize-controller** al sync. Configurazione in
`k8s/clusters/dyson/*.yaml`:

```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

Il Secret `sops-age` in namespace `flux-system` contiene la chiave privata
age. k3s lo applica al boot (via symlink sops-nix), quindi Flux lo trova già
pronto al primo sync.

## Workflow: cifrare un nuovo secret

### Secret host

```bash
# Crea il file YAML/DOTENV con dati in chiaro
cat > secrets/my-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
stringData:
  password: supersecret
EOF

# Cifra con sops
sops --encrypt --in-place secrets/my-secret.yaml

# Verifica
head secrets/my-secret.yaml  # deve avere blocchi sops: ... ENC[AES256_GCM...
```

### Secret k8s

```bash
# Crea un Secret Kubernetes
kubectl create secret generic my-secret \
  --namespace=myns \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > k8s/apps/myapp/secret.yaml

# Cifra
sops --encrypt --in-place k8s/apps/myapp/secret.yaml
rm k8s/apps/myapp/secret.yaml  # rimuovi plaintext

# Commit
git add k8s/apps/myapp/secret.enc.yaml
git commit -m "feat(k8s): add myapp secret"
git push
# Flux decifra e applica al prossimo sync (~10min)
```

## Workflow: aggiornare un secret esistente

```bash
# Decifra, modifica, ricifra
sops secrets/my-secret.yaml
# (apre $EDITOR, modifica valori, salva → ricifra automatico)

# Per k8s:
sops k8s/apps/myapp/secret.enc.yaml
# Salva → ricifra → Flux riconcilia
```

## Workflow: aggiungere una nuova macchina

Se in futuro aggiungi un secondo host NixOS al repo:

1. Genera una nuova chiave age per il nuovo host:
   ```bash
   age-keygen -o new-host-key.txt
   ```
2. Aggiungi la chiave pubblica a `.sops.yaml`:
   ```yaml
   creation_rules:
     - path_regex: ...
       age: "age1oldkey...,age1newhostkey..."
   ```
3. Ri-cifra tutti i secret con la nuova chiave:
   ```bash
   sops updatekeys -y secrets/*.enc.yaml k8s/**/*.enc.yaml
   ```
4. Aggiungi la chiave privata al nuovo host (via USB, password manager, ecc.)

## gitleaks

`gitleaks` gira in CI su ogni push/PR. Scansiona tutta la history
(`fetch-depth: 0`). Se committi un secret per errore:

1. **Ruota immediatamente** il secret (Cloudflare token, R2 keys, ecc.)
2. Rimuovi dalla history: `git filter-repo` o BFG
3. Push forzato
4. Aggiorna `.sops.yaml` se necessario

## Audit

Per vedere cosa è stato decifrato (debug):
```bash
# Lista secret host decifrati
ls -la /run/secrets/
ls -la /run/secrets/k3s/
ls -la /run/secrets/backup/

# Verifica che i secret k8s siano decifrati da Flux
k3s kubectl -n myns get secret my-secret -o jsonpath='{.data.password}' | base64 -d
```

## Riferimenti

- [sops GitHub](https://github.com/getsops/sops) — tool CLI
- [sops-nix](https://github.com/Mic92/sops-nix) — modulo NixOS
- [age](https://github.com/FiloSottile/age) — crittografia
- [Flux SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/) — decifrazione in k8s
