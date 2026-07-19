# Installazione NixOS — Nebula

Guida operativa per installare NixOS baremetal su Nebula (Dell Optiplex 3050).

nixos-anywhere installa NixOS via SSH su qualsiasi Linux già avviato sul target,
usando disko per partizionare. Il target deve essere avviato con un'immagine
NixOS (custom o ufficiale) con SSH attivo e la chiave della workstation
autorizzata in `/root/.ssh/authorized_keys`.

**Prima installazione**: build ISO custom da flake → flash USB → boot → nixos-anywhere.
**Reinstall futuri**: nixos-anywhere direttamente, NixOS risponde già su SSH.

> **Prerequisito**: backup di qualsiasi dato da conservare prima di procedere.

## Prerequisiti

- Workstation con `nix` installato e flakes abilitati
- Nebula raggiungibile via SSH:
  - come `root` durante l'install (nixos-anywhere esegue disko/install)
  - come `cosimo` per operazioni post-install (sudo nopasswd via `wheel`)
- Chiave SSH della workstation autorizzata sul target (vedi `modules/keys.nix`)
- Chiave age privata per sops accessibile dalla workstation

> **Workstation NixOS vs WSL/macOS**: su workstation NixOS hai `nixos-rebuild` e
> `nixos-anywhere` come binari nativi. Su WSL/macOS li lanci via
> `nix run nixpkgs#nixos-rebuild --` o `nix run github:nix-community/nixos-anywhere --`.

---

## Step 1 — Prepara USB con ISO NixOS custom

L'installer ISO custom (configurazione in `hosts/installer/`) ha già la chiave
SSH della workstation e IP statico configurati, quindi al boot nebula è subito
raggiungibile senza setup aggiuntivo.

```bash
cd ~/astra
nix build .#nixosConfigurations.installer.config.system.build.isoImage
# Risultato in result/iso/nixos-minimal-*.iso
# Flash su USB (>= 4GB):
sudo dd if=result/iso/nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

Boot nebula da USB (F12 → boot menu Dell). Il sistema si avvia con:
- IP statico `192.168.178.2/24`, gateway `192.168.178.1`
- sshd attivo con `PermitRootLogin yes` e `PasswordAuthentication yes`
- `authorized_keys` = chiave della workstation (via `modules/keys.nix`)

Verifica connettività:
```bash
ssh -o StrictHostKeyChecking=accept-new root@192.168.178.2 uname -a
# Linux nixos 6.12.x ... x86_64 GNU/Linux
```

> **Alternativa: Debian minimal**. Se preferisci partire da Debian (più familiare
> per il debug live), scarica la netinst ISO e installa con SSH server, IP
> statico, e `PermitRootLogin yes`. Stesso punto di arrivo.

---

## Step 2 — Prepara i secrets (una tantum, prima della prima install)

Sulla workstation, se non hai già una chiave age:

```bash
# Genera la chiave age (una volta per tutto il repo)
age-keygen -o ~/.config/sops/age/keys.txt
# Output:
#   Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# Salva la chiave pubblica in .sops.yaml (root del repo) al posto di AGE_PUBLIC_KEY

# Popola i file secret (vedi secrets/*.enc.yaml per lo schema):
#   secrets/flux-git-auth.enc.yaml       (SSH key per Flux)
#   secrets/flux-sops-age.enc.yaml       (chiave age per k8s)
#   secrets/rclone-env.enc.yaml          (credenziali R2)

# Cifra con sops (solo se hai rigenerato .sops.yaml; i file .enc.yaml in repo
# sono già cifrati con la chiave corrente)
sops --encrypt --in-place secrets/flux-git-auth.enc.yaml
sops --encrypt --in-place secrets/flux-sops-age.enc.yaml
sops --encrypt --in-place secrets/rclone-env.enc.yaml

# Aggiungi la tua SSH pubblica in modules/common.nix:
#   users.users.cosimo.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];

# hostId univoco per ZFS (una volta per host)
head -c4 /dev/urandom | od -A none -t x4
# Aggiorna in hosts/nebula/hardware.nix → networking.hostId
```

> **Path chiave age**: il default sops-nix è `~/.config/sops/age/keys.txt`, ma il
> repo usa `/persist/sops/age/keys.txt` come path sul target dopo l'install
> (vedi `modules/common.nix` riga 27). Sulla workstation puoi tenerla dove
> preferisci — basta che sia raggiungibile allo Step 3.1.

> **Backup della chiave age FONDAMENTALE**: senza la chiave privata, i secret
> sono irrecuperabili. Conservala in password manager + copia offline cifrata.
> Il backup rclone NON include la chiave.

---

## Step 3 — Esegui nixos-anywhere

nixos-anywhere si connette a Nebula via SSH, partiziona il disco con disko,
installa NixOS e riavvia.

⚠️ **Distruttivo**: cancella tutto su `/dev/sda` del target.

### 3.1 Prepara la chiave age per `--extra-files`

nixos-anywhere deve pushare la chiave age su `/persist/sops/age/keys.txt` PRIMA
del primo switch (altrimenti sops-nix non riesce a decifrare i secret al boot).
La struttura della dir passata a `--extra-files` deve rispecchiare il path di
destinazione sul target.

```bash
# Esempio: workstation con chiave in ~/.config/sops/age/keys.txt
EXTRA=$(mktemp -d)
mkdir -p "$EXTRA/persist/sops/age"
cp ~/.config/sops/age/keys.txt "$EXTRA/persist/sops/age/keys.txt"
chmod 600 "$EXTRA/persist/sops/age/keys.txt"
echo "$EXTRA"  # ricorda questo path per il prossimo comando
```

> **Adatta il path sorgente** a dove tieni effettivamente la chiave
> (es. `~/age/age-houston.txt` → copia in `$EXTRA/persist/sops/age/keys.txt`).

### 3.2 Lancia nixos-anywhere

```bash
cd ~/astra
nix run github:nix-community/nixos-anywhere -- \
  --flake .#nebula \
  --target-host root@192.168.178.2 \
  --build-on local \
  --extra-files "$EXTRA"
```

> **Workstation NixOS**: puoi usare direttamente `nixos-anywhere` se hai il
> binario installato. Per WSL/macOS la forma `nix run ... --` è obbligatoria.

nixos-anywhere esegue in sequenza:
1. Connessione SSH (root, no password — usa la chiave autorizzata)
2. `disko` → partiziona `/dev/sda` con ZFS (pool `tank`)
3. Copia la chiave age in `/persist/sops/age/keys.txt` (via `--extra-files`)
4. `nixos-install` con il flake `.#nebula`
5. Reboot in NixOS

Durata: 10-30 min a seconda di quante cose scarica/builda. Output in tempo reale.

Vedi [02-storage.md](02-storage.md) per il layout ZFS dettagliato.

---

## Step 4 — Switch completo e verifica post-install

Dopo il reboot automatico, nebula è in NixOS ma con la configurazione "base" di
nixos-anywhere. Per attivare k3s, Technitium, Flux, etc., serve uno `switch`
completo.

### 4.1 Switch completo

```bash
cd ~/astra

# Workstation NixOS:
nixos-rebuild switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 \
  --build-host localhost \
  --use-remote-sudo

# Workstation WSL/macOS (senza nixos-rebuild nativo):
nix run nixpkgs#nixos-rebuild -- switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 \
  --build-host localhost \
  --use-remote-sudo
```

> **`--use-remote-sudo`**: serve perché nixos-rebuild via SSH esegue
> `nix-env --set` e `switch-to-configuration` come utente target, ma entrambi
> richiedono root per scrivere in `/nix/var/nix/profiles/`. Il flag fa il
> `sudo` su quei comandi, sfruttando `wheelNeedsPassword = false` di
> `modules/common.nix` riga 11. Senza di esso, su target non-root, fallisce
> con `Permission denied` su `/nix/var/nix/profiles/.0_system`.

Adesso partono tutti i moduli dichiarati nel flake (Technitium, k3s, sops-nix,
rclone-backup timer).

### 4.2 Verifica

```bash
# SSH come cosimo (sudo nopasswd)
ssh cosimo@192.168.178.2

# Pool ZFS e persist
sudo zpool status tank
sudo zfs list
ls -la /persist/sops/age/                       # deve contenere keys.txt

# sops-nix ha decifrato i secret? (deve essere popolato)
sudo ls /run/secrets/                            # k3s/, backup/, ...
sudo ls /run/secrets/k3s/                        # flux-git-auth, flux-sops-age
sudo ls /run/secrets/backup/                     # rclone-env

# Servizi host
sudo systemctl status technitium-dns-server
sudo systemctl status k3s
sudo systemctl status rclone-backup.timer        # attivo, prossimo run alle 03:00

# k3s
sudo k3s kubectl get nodes
# NAME      STATUS   ROLES                  AGE     VERSION
# nebula   Ready    control-plane,master   2m      v1.30.x+k3s1

sudo k3s kubectl get pods -A | head
# Tutti i pod devono essere Running (coredns, traefik, flux-system, ...)

# CoreDNS custom (forward a Technitium)
sudo k3s kubectl -n kube-system get configmap coredns
# Deve esistere con il Corefile che forward a 192.168.178.2:53

# Flux
sudo k3s kubectl -n flux-system get pods
sudo k3s flux get kustomizations
# Tutte le Kustomization devono essere Ready
```

### Troubleshooting rapido post-install

- **`/run/secrets/` vuoto dopo switch** → la chiave age non era in
  `/persist/sops/age/keys.txt` al boot. Ricontrolla Step 3.1 e rifai
  `nixos-rebuild switch` (i secret non si decifrano finché la chiave non c'è).
- **k3s non parte** → `journalctl -u k3s`. Di solito porta 6443 occupata o
  errore di configurazione. Flannel non richiede bootstrap esterno.
- **Flux non si connette a GitHub** → verifica la SSH key in
  `secrets/flux-git-auth.enc.yaml` e che la chiave pubblica sia aggiunta come
  Deploy Key su GitHub (read-only).
- **SSH da workstation rifiutato dopo reboot** → il sistema installato ha
  `PasswordAuthentication = false` e richiede la chiave privata. Verifica che
  `modules/common.nix` contenga la tua chiave pubblica e che tu ce l'abbia in
  `~/.ssh/id_ed25519`.

---

## Step 5 — Configurazione Technitium via web UI

Technitium è un servizio host, non gestito dal flake. La zona DNS, blocklist e
config si fanno via web UI:

```bash
# Dalla workstation, tunnel SSH verso la web UI
ssh -L 5380:127.0.0.1:5380 cosimo@192.168.178.2
# Apri browser su http://127.0.0.1:5380
```

Configurazione minima:
- Crea zona autoritativa `lab.paroparo.it`
- Aggiungi record wildcard `*.lab.paroparo.it → 192.168.178.2`
- Configura upstream DoH Cloudflare
- Abilita recursion + DNSSEC validation
- Blocklist: incolla le URL da `hosts/nebula/dns-blocklists.txt` (HaGeZi Pro +
  Steven Black + AdGuard DNS filter)

Il file [`hosts/nebula/dns-zone.lab.paroparo.it`](../hosts/nebula/dns-zone.lab.paroparo.it)
contiene la zona BIND completa (record espliciti, CAA, SPF) — importabile
via UI per non ricreare a mano.

Vedi [04-dns-technitium.md](04-dns-technitium.md) per dettagli e la checklist
completa (anche nell'header del file [`hosts/nebula/technitium.nix`](../hosts/nebula/technitium.nix)).

## Step 6 — Verifica end-to-end

```bash
# Da un client sulla LAN
dig @192.168.178.2 lab.paroparo.it
# Deve risolvere (Technitium ha la zona)

dig @192.168.178.2 uptime.lab.paroparo.it
# Wildcard → 192.168.178.2 (Traefik k3s)

# HTTPS valido
curl -v https://uptime.lab.paroparo.it
# Cert Let's Encrypt valido, servizio Uptime Kuma raggiungibile
```

---

## Upgrade futuro

Per aggiornare NixOS o un pacchetto:

```bash
# Update flake.lock (pin nixpkgs nuovo)
nix flake update --commit nixpkgs

# Workstation NixOS — build e applica
nixos-rebuild switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo

# Workstation WSL/macOS
nix run nixpkgs#nixos-rebuild -- switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo
```

Per aggiornare altri Helm chart (traefik, cert-manager):
1. Modifica versione nel rispettivo `helmrelease.yaml` in `k8s/infra/`
2. Commit → Flux riconcilia

---

## Disaster recovery

Per ricostruire da zero:

1. USB NixOS minimal + procedura Step 1-4
2. Cifra di nuovo i secret con sops (devi avere la chiave age backuppata!)
3. Verifica che i backup rclone siano disponibili su R2

**Importante**: la chiave age deve essere backuppata FUORI dal repo (password
manager + copia offline). Senza chiave, i secret sono irrecuperabili.

### Restore da R2

```bash
# Setup rclone con credenziali
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=xxx
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=xxx
export RCLONE_CONFIG_R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com

# Restore Technitium
rclone sync r2:nebula-backup/technitium/ /var/lib/technitium-dns-server/
systemctl restart technitium-dns-server

# Restore k3s state (richiede stop k3s prima)
systemctl stop k3s
rclone sync r2:nebula-backup/k3s/ /var/lib/rancher/k3s/
systemctl start k3s
```

---

## Troubleshooting reference

### ZFS non si importa al boot

Verifica la `hostId` in `hosts/nebula/hardware.nix` (deve corrispondere
all'ID del disco). Da live USB: `zpool import -f tank`.

### CoreDNS non delega a Technitium

Verifica che il ConfigMap `coredns` esista in `kube-system`:
```bash
k3s kubectl -n kube-system get configmap coredns -o yaml
```

E che il symlink sia presente:
```bash
ls -la /var/lib/rancher/k3s/server/manifests/00-coredns-custom.yaml
```

### DNS non risolve da client LAN

Verifica firewall NixOS:
```bash
# Sul server
ss -tlnp | grep :53
# tecnitium-dns-server deve essere in ascolto

# Da un client
dig @192.168.178.2 lab.paroparo.it
```

Se il firewall blocca: aggiungi le porte in `hosts/nebula/networking.nix`.
