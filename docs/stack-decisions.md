# Astra — Stack Decisioni e Motivazioni

Documento di riferimento per le **scelte architetturali** di Astra, con motivazione,
alternative scartate e rischio a lungo termine. Ogni decisione ha uno stato:
- 🟢 **applicato** = in produzione
- 🟡 **parziale** = in corso
- 🔴 **proposto** = documentato, non implementato

---

## Mappa decisioni

| #    | Decisione                            | Stato    | Note |
|------|--------------------------------------|----------|------|
| D1   | CNI: Flannel (bundled k3s)           | 🟢 applicato | Default k3s, sufficiente su single-node |
| D2   | CoreDNS bundled k3s + ConfigMap custom | 🟢 applicato | Delega split-horizon a Technitium |
| D3   | Rimuovere NVMe fisicamente           | 🟢 applicato | Single disk /dev/sda |
| D4   | ArgoCD → Flux CD v2                  | 🟢 applicato | Native SOPS, niente plugin esterni |
| D5   | Kubelet tuning k3s (low-RAM)         | 🟢 applicato | In `hosts/nebula/k3s.nix` → `extraFlags` |
| D6   | Sealed Secrets → SOPS + age          | 🟢 applicato | Unificato host (sops-nix) + k8s (Flux SOPS) |
| D7   | Beszel monitoring                    | 🟢 applicato | Hub in k3s + agent host NixOS attivi |
| D8   | RAM upgrade 16 → 32 GB               | 🟡 parziale | Prerequisito hardware, non ancora fatto |
| D9   | Pi-hole v6 → Technitium DNS          | 🟢 applicato | Modulo NixOS nativo (nixpkgs) |
| D10  | Backup rclone → Cloudflare R2        | 🟡 in pausa | Modulo NixOS pronto, disabilitato 2026-07-19 (refactor on hold) |
| D11  | Alerting channel (ntfy)              | 🔴 proposto | Beszel + Uptime Kuma → ntfy |
| D12  | Dependency updates (Renovate)        | 🔴 proposto | Aggiornamenti automatici Helm chart, Nix packages |
| D13  | ZFS encryption rimossa               | 🟢 applicato | No threat model reale su astra; complessità TPM2 > benefici |

---

## D1 — Flannel (bundled k3s)

**Problema**: bootstrap Cilium su NixOS fragile (chicken-and-egg pre-CNI, plugin path non standard, servizio systemd custom one-shot).

**Scelta**: Flannel bundled k3s. Default, zero bootstrap esterno, sufficiente su single-node (routing L3, niente NetworkPolicy avanzate).

**Futuro**: Cilium aggiungibile via Flux `HelmRelease` quando il cluster è stabile.

**Rischio**: 🟢 basso.

---

## D2 — CoreDNS bundled + ConfigMap custom

**Problema**: split-horizon per `lab.paroparo.it` (forward a Technitium locale).

**Scelta**: ConfigMap `coredns` in `hosts/nebula/k3s.nix` → `manifests."coredns-custom"`. k3s applica manifest con prefisso `00-` prima del CoreDNS bundled, sovrascrive il Corefile di default (split-horizon via `forward . 192.168.178.2:53`).

**Vantaggi**: zero helm chart, config versionata nel flake, idempotente al boot.

**Rischio**: 🟢 basso.

---

## D3 — Rimozione NVMe (single disk)

### Problema

Il vecchio setup aveva due dischi:
- SATA SSD 500 GB (`/dev/sda`, OS Proxmox)
- NVMe 500 GB (`/dev/nvme0n1`, VM root + PV k3s)

L'NVMe era fonte di calore/rumore e non usato in modo critico.

### Scelta: rimozione NVMe nel setup NixOS

Nel nuovo setup NixOS c'è solo `/dev/sda` (500 GB). ZFS usa tutto lo spazio
disponibile. PV k3s vivono in `tank/volumes` (ZFS dataset).

### Rischio a lungo termine

🟢 Nessuno — meno dischi = meno roba che può rompersi.

---

## D4 — ArgoCD → Flux CD v2

**Problema**: ArgoCD ha ~500 MB RAM idle, drift via UI, SOPS via plugin esterno.

**Scelta**: Flux CD v2 (CNCF Graduated). SOPS nativo (kustomize-controller), Helm SDK nativo, retry fino a convergenza.

**Trade-off accettato**: niente web UI, solo CLI (`flux get all`, `kubectl describe kustomization`, `flux logs`).

**Rischio**: 🟢 basso.

---

## D5 — Kubelet tuning k3s (low-RAM)

### Problema

k3s di default non è ottimizzato per single-node con RAM limitata.

### Scelta: `extraFlags` in `hosts/nebula/k3s.nix`

```nix
services.k3s.extraFlags = toString [
  "--disable=traefik"              # Traefik via Flux
  "--disable=metrics-server"       # Beszel copre monitoring
  "--write-kubeconfig-mode=0644"   # kubeconfig leggibile da utente
];
```

> Note:
> - `--disable=servicelb` rimosso: klipper-lb è necessario per esporre Traefik
>   come `Service type=LoadBalancer` su 80/443 (vedi
>   `k8s/infra/traefik/install/helmrelease.yaml`).
> - `--disable=local-storage` rimosso: il PVC `local-path` è usato dalle app
>   (uptime-kuma, beszel-hub) per il `local-path` storage class.
> - `--flannel-backend=none` e `--disable-network-policy` sono stati
>   rimossi insieme a Cilium (D1). Flannel è attivo di default.

### Rischio a lungo termine

🟢 Basso — flag k3s/kubelet standard e documentati.

---

## D6 — Sealed Secrets → SOPS + age (unificato)

**Problema**: due toolchain secrets (Sealed Secrets per k8s, Ansible Vault per host). Due modi per cifrare, due punti di rottura.

**Scelta**: SOPS + age ovunque. Stessa chiave age in `.sops.yaml`. `secrets/*.enc.yaml` → sops-nix per host (mount `/run/secrets/`); `k8s/**/*.enc.yaml` → Flux kustomize-controller per k8s (Secret resource). PR diff leggibile (chiavi visibili, valori cifrati).

**Rischio**: 🟢 basso — SOPS maturo (2016), [getsops org](https://github.com/getsops/sops).

---

## D7 — Beszel monitoring

### Problema

Prometheus + Grafana + Loki era in HOLD: troppo complesso, ~500 MB RAM.
Serve sapere CPU/RAM host, disco, container up/down.

### Scelta: Beszel + Uptime Kuma

- **Uptime Kuma**: HTTP/TCP/DNS check, status page. In k3s (HelmRelease).
- **Beszel**: metriche host (CPU, RAM, disco, I/O, rete, temperatura). Hub in k3s + agent su host NixOS.

### Limitazione: K8s metrics

Beszel non ha supporto K8s nativo. Per metriche per Pod/Deployment come
oggetti K8s serve altro (VictoriaMetrics o simile). Per Nebula è accettabile:
l'interesse è il nodo, non l'introspection dei workload.

### Stato

🟢 Fatto — Hub in k3s + agent su `nebula` (`hosts/nebula/beszel-agent.nix`, 2026-07-19). Manca solo l'alerting (D11).

### Rischio a lungo termine

🟡 Medio — progetto giovane (2024), 22k stars, MIT, non CNCF.

---

## D8 — RAM upgrade 16 → 32 GB

### Problema

Con 16 GB RAM: NixOS host (~1 GB) + k3s (~500 MB) + Traefik + cert-manager +
Beszel + Flux = headroom limitato.

### Scelta: DDR4 SO-DIMM 2×16 GB (~35€)

Prerequisito per workload Fase 4 (Jellyfin transcoding) e per buffer generale.

### Stato

🟡 Parziale — non ancora acquistato/installato.

### Rischio a lungo termine

🟢 Basso — hardware commodity, nessun lock-in.

---

## D9 — Pi-hole v6 → Technitium DNS

### Problema

Pi-hole è un ad-blocker DNS, non un server DNS completo. Per il pattern
Nebula (`*.lab.paroparo.it` interno → 192.168.178.2, split horizon) servono:
- Zona primaria autoritativa per `lab.paroparo.it`
- Record wildcard gestibile
- Split horizon (risposta diversa per query interne vs esterne)
- DoH/DoT built-in

Pi-hole v6 non supporta nessuno di questi nativamente.

### Scelta: Technitium DNS (modulo NixOS nativo)

`pkgs.technitium-dns-server` 15.x da `nixpkgs-unstable` (vedi
`flake.nix` → `specialArgs.unstable`) con modulo
`services.technitium-dns-server`:
- systemd hardened (`DynamicUser`, `NoNewPrivileges`, `ProtectSystem=strict`)
- `StateDirectory` gestito automaticamente
- Web UI su `0.0.0.0:5380` (raggiungibile solo via loopback o Traefik reverse
  proxy — vedi firewall custom in `hosts/nebula/technitium.nix`)
- Niente container/Docker, gira come servizio host
- Recursion + DNSSEC validation attivi, blocklist HaGeZi + Steven Black + AdGuard
  (vedi `hosts/nebula/dns-blocklists.txt`)

Vedi [04-dns-technitium.md](04-dns-technitium.md) per la configurazione completa.

### Rischio a lungo termine

🟡 Medio — sviluppatore singolo (Shreyas Zare). Attivo dal 2017, GPL-3, forkabile.

---

## D10 — Backup rclone → Cloudflare R2

### Problema

Lo stato attuale (no backup off-site) non è un DR reale. I dati che **non** si
possono ricostruire da Git:
- `/var/lib/technitium-dns-server/` (zona DNS, blocklist)
- `/var/lib/rancher/k3s/` (etcd, certificati k3s)
- `/home/` (dotfiles)

### Scelta: rclone crypt → Cloudflare R2

- **Cloudflare R2**: S3-compatible, free tier 10 GB, **zero egress fees**
- **rclone**: client universale, supporta S3 + cifratura client-side
- **systemd timer NixOS** (`hosts/nebula/backup.nix`): esecuzione notturna alle 03:00

```nix
systemd.services.rclone-backup = {
  serviceConfig.ExecStart = ''
    rclone sync /var/lib/technitium-dns-server r2:nebula-backup/technitium/
    rclone sync /var/lib/rancher/k3s r2:nebula-backup/k3s/
    rclone sync /home r2:nebula-backup/home/
  '';
};
systemd.timers.rclone-backup = {
  timerConfig.OnCalendar = "*-*-* 03:00:00";
  timerConfig.Persistent = true;
};
```

Configurazione R2 in `secrets/rclone-env.enc.yaml` (cifrato con sops-nix).

### Stato

🟡 **In pausa** dal 2026-07-19 (commit `e71a299`). `hosts/nebula/backup.nix`
esiste ed è funzionante, ma è **commentato** in `hosts/nebula/default.nix`
(`#./backup.nix`). Il file termina con il commento
`#MESSO ON HOLD FINO A NUOVA IDEA`. Nessun timer rclone è attivo. Il modulo
verrà ripreso con un nuovo approccio (da definire).

### Rischio a lungo termine

🟢 Basso — rclone maturo (~45k stars), Cloudflare R2 servizio commerciale stabile.

---

## D11 — Alerting channel (ntfy)

### Problema

Beszel e Uptime Kuma hanno alert configurabili ma senza un canale notifiche
sono inutili. Senza notifiche, disco pieno o servizio down vengono scoperti
per caso.

### Scelta: ntfy (self-hosted o `ntfy.sh`)

**ntfy** è push notification self-hosted. Sia Beszel che Uptime Kuma lo
supportano nativamente.

`ntfy.sh` pubblico è OK per iniziare (topic privato = stringa casuale).
Migra a self-hosted se vuoi eliminare la dipendenza esterna.

### Stato

🔴 Proposto — non ancora configurato.

### Rischio a lungo termine

🟢 Basso — MIT, 18k stars, attivamente mantenuto.

---

## D12 — Dependency updates (Renovate)

### Problema

Le versioni sono pinnate ovunque (Helm chart, Nix packages) ma senza un
meccanismo automatico di bump. Nel tempo: Cilium EOL silenzioso,
cert-manager non aggiornato, ecc.

### Scelta: Renovate Bot

Configurazione minima in `.renovaterc.json`:
- Aggiorna Helm chart in `HelmRelease` Flux
- Aggiorna Nix packages (via flake-update detection)
- Aggiorna GitHub Actions
- Schedule settimanale

### Stato

🔴 Proposto — `.renovaterc.json` esiste ma Renovate non è ancora attivato
su GitHub.

### Rischio a lungo termine

🟢 Basso — Mend-backed, usato in migliaia di repo.

---

## D13 — ZFS encryption rimossa

### Problema

`tank/root` era cifrato (AES-256-GCM) con chiave in TPM2 (`modules/zfs-tpm2.nix`).
Questo aggiungeva:
- Dipendenza da TPM2 al boot (chip presente ma non standard su Optiplex 3050)
- Prompt al boot se TPM2 falliva
- Modulo NixOS extra (`zfs-tpm2.nix`) da mantenere
- Complessità di recovery (perdita TPM = perdita dati)

### Threat model reale

Astra è una fleet domestica su rete casuale. Il rischio di furto fisico con
attacco ai dati a disco è trascurabile. I dati sensibili (credenziali,
certificati) sono già protetti da SOPS + age. La cifratura del filesystem di
root non aggiungeva protezione pratica.

### Scelta: ZFS senza cifratura

`tank/root` e tutti i dataset senza `encryption`, `keyformat`, `keylocation`.
ZFS resta per snapshot, CoW, compressione zstd — i motivi per cui è stato
scelto.

### Possibilità futura

Dataset cifrati specifici (es. `tank/secrets`) restano possibili senza
impatto sul boot, se in futuro il threat model cambia.

### Rischio a lungo termine

🟢 Nessuno sul fronte operativo. Se il threat model cambiasse (colocation,
ufficio), rivalutare.

---

## Note aperte

### CI: kubeconform

Schema Flux già incluso nel catalogo datree. Aggiornamenti futuri dei CRD
incluso automaticamente.

### DR test

Da eseguire almeno una volta dopo la migrazione NixOS:
1. `nix flake check` verde
2. `nixos-install --flake .#nebula` su disco pulito
3. Verifica che k3s, Flannel, Flux ripartano
4. Verifica che Technitium risolva `lab.paroparo.it`
5. Verifica che il backup rclone sia leggibile da R2 *(in pausa, da aggiornare quando D10 viene ripreso)*

Pianificare come sprint stand-alone dopo il cutover.
