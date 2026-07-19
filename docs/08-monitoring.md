# Monitoring — Uptime Kuma + Beszel

Stack di monitoring leggero: Uptime Kuma per availability, Beszel per metriche
host. Entrambi girano come pod k8s, gestiti da Flux.

## Uptime Kuma — status page + check

[Uptime Kuma](https://github.com/louislam/uptime-kuma) è un monitor self-hosted
con UI web. Supporta HTTP, TCP, DNS, ping, push, e molti altri check.

### Deploy

In [`k8s/apps/uptime-kuma/`](../k8s/apps/uptime-kuma/):
- `namespace.yaml` — namespace dedicato
- `deployment.yaml` — Uptime Kuma 1.x
- `service.yaml` — ClusterIP
- `ingress.yaml` — `uptime.lab.paroparo.it`
- `pvc.yaml` — 5 Gi per la DB SQLite

### Configurazione

Dopo il primo deploy:
1. Accedi a `https://uptime.lab.paroparo.it`
2. Crea utente admin
3. Aggiungi monitor per ogni servizio:
   - `nebula.lab.paroparo.it` (HTTP, keyword check)
   - `k3s.lab.paroparo.it` o equivalente (TCP 6443)
   - DNS check: `dig @192.168.178.2 lab.paroparo.it` (keyword: NXDOMAIN/NOERROR)
   - Servizi app: `beszel.lab.paroparo.it`, `homepage.lab.paroparo.it`, ecc.
4. (Opzionale) Status page pubblica: `status.lab.paroparo.it`
5. Notifiche: configurare canale (vedi sotto)

## Beszel — metriche host

[Beszel](https://github.com/henrygd/beszel) è un monitor leggero (hub + agent)
per metriche host: CPU, RAM, disco, I/O, rete, temperatura.

### Deploy

In [`k8s/apps/beszel/`](../k8s/apps/beszel/):
- `namespace.yaml` — namespace `beszel` con label `pod-security.kubernetes.io/enforce: privileged`
- `hub-deployment.yaml` — Beszel hub (henrygd/beszel:0.18.7)
- `hub-service.yaml` — ClusterIP
- `hub-pvc.yaml` — DB hub (1 Gi, storage class `local-path`)
- `hub-ingress.yaml` — `beszel.lab.paroparo.it`

> **Stato attuale**: solo l'hub è deployato. Non c'è ancora un agent
> `DaemonSet` nel cluster (vedi sotto per la limitazione K8s).

### Limitazione: agent su host NixOS

Beszel non ha supporto K8s nativo. L'agent ideale sarebbe un pod con
`privileged` + `hostPath` su `/proc`, `/sys`, `/var/lib/rancher/k3s`, ma
richiede la label namespace `pod-security.kubernetes.io/enforce: privileged`
(già impostata). Metriche host OK, metriche per Pod/Deployment come oggetti
K8s no.

L'agent sul **host NixOS** è implementato in `hosts/nebula/beszel-agent.nix`
(modulo `services.beszel.agent`): legge la enrollment key da
`secrets/beszel-agent-key.enc.yaml` (sops-nix) e popola l'hub
`beszel.lab.paroparo.it` con CPU/RAM/disco/rete di `nebula`.

## Notifiche

Entrambi supportano notifiche push. Canali consigliati:

| Canale | Tipo | Note |
|--------|------|------|
| **ntfy** | Push notification | Self-hosted o `ntfy.sh` pubblico (free tier) |
| Telegram | Bot | Richiede bot token |
| Discord | Webhook | Gratuito |
| Email | SMTP | Lento, ma sempre funziona |

### ntfy (consigliato)

[ntfy](https://ntfy.sh) è push notification self-hosted. ~10 MB RAM.

1. Crea topic: `https://ntfy.sh/nebula-<random-string>` (stringa random = privatezza)
2. Sottoscrivi dal telefono (app ntfy)
3. Configura in Uptime Kuma e Beszel

> Vedi `stack-decisions.md#d11--alerting-channel-ntfy` per il setup completo
> (proposto, non ancora implementato).

## Backup

- Uptime Kuma: PV `5Gi` con SQLite DB. Backup con rclone in `/var/lib/rancher/k3s/...`
  (*in pausa dal 2026-07-19, vedi [03-backup.md](03-backup.md)*).
- Beszel: PV con DB hub. Stesso backup.

## Verifica

```bash
# Uptime Kuma raggiungibile
curl -v https://uptime.lab.paroparo.it
# HTTP 200, UI visibile

# Beszel raggiungibile
curl -v https://beszel.lab.paroparo.it
# HTTP 200, login page

# Metriche raccolte
# Da Beszel UI: dashboard con CPU, RAM, disco di nebula
```

## Roadmap

| Decisione | Stato | Note |
|-----------|-------|------|
| D7 — Beszel monitoring  | 🟡 parziale | Hub in k3s + agent host NixOS attivi; manca solo alerting |
| D11 — Alerting ntfy | 🔴 proposto | Da configurare dopo Beszel agent host |

## Alternative considerate (per memoria)

- **Prometheus + Grafana + Loki**: in HOLD. Troppo complesso (~500 MB+ RAM),
  centinaia di MB di storage. Per single-host è overkill.
- **VictoriaMetrics + Grafana**: più leggero di Prometheus. Da rivalutare se
  servono PromQL o log aggregation.
- **Netdata**: buono ma più pesante di Beszel, no UI comparabile.
- **Glances**: troppo minimale, no storage storico.

## Riferimenti

- [Uptime Kuma](https://github.com/louislam/uptime-kuma)
- [Beszel](https://github.com/henrygd/beszel)
- [ntfy](https://ntfy.sh)
