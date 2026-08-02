# Astra — Istruzioni di progetto

> **STOP — prima di qualsiasi azione leggi [`docs/roadmap.md`](docs/roadmap.md) e §Servizi qui sotto integralmente.**
> Non scrivere codice, non fare ricerche, non proporre nulla finché non hai letto lo stato corrente.
> Vale per ogni sessione, anche breve.

Questo file è la **fonte unica** delle istruzioni di progetto per gli agenti.
Riferimenti on-demand (caricare quando serve):
- [`docs/roadmap.md`](docs/roadmap.md) — piano per fasi e sprint
- [`docs/stack-decisions.md`](docs/stack-decisions.md) — decisioni architetturali motivate
- [`docs/0N-*.md`](docs/) — un doc per argomento operativo
- [`docs/README.md`](docs/README.md) — indice navigabile

> Per il setup globale di opencode (permission, MCP, provider) vedi
> `~/.config/opencode/opencode.jsonc`.

## Progetto

Homelab su Dell Optiplex 3050 (`nebula`, nodo principale) e Raspberry Pi 4
(`taiga`, satellite per stampante 3D) con **NixOS baremetal** (no hypervisor).
k3s come servizio host, Technitium DNS come servizio NixOS nativo, Flux CD
per GitOps k8s, TLS pubblico via Let's Encrypt (DNS-01 Cloudflare), DNS
interno via Technitium.

> Progetto anche **didattico**: si costruisce un pezzo alla volta, capendo cosa
> fa. Il piano completo è in **[docs/roadmap.md](docs/roadmap.md)**.

## Utente

Cosimo Casini — Cloud Architect e Solution Architect con background ML applicato. Programmatore esperto (Python, infrastructure cloud, Klipper).

- Risposte dirette, no preamble/riepilogo finale
- Una sola domanda per turno se serve chiarimento
- Non spiegare cose ovvie
- Preferisce SQL diretto su DuckDB per query ad-hoc

## Modalità di lavoro

Questo repo è anche un percorso di **apprendimento**: l'obiettivo non è solo
avere l'infrastruttura, ma capirla. Quindi:

- **Spiega ogni file PRIMA di crearlo o modificarlo.** Descrivi a cosa serve,
  cosa contiene e perché, poi crealo. In alternativa costruiamolo insieme un
  pezzo alla volta.
- Niente raffiche di file creati in blocco senza spiegazione.
- Procedi un passo alla volta, lasciando spazio a domande e verifiche.
- **Prima la lista dei servizi, poi i file.** Si lavora per **sprint** atomici
  guidati da [docs/roadmap.md](docs/roadmap.md): un servizio alla volta, con
  Definition of Done, commit, poi il successivo. Non saltare avanti nelle fasi.
- Segnala sempre i punti incerti come "da verificare", non darli per oro colato.

## Lingua e stile

- Rispondi in **italiano** salvo quando l'utente scrive in inglese.
- Stile conciso: niente introduzioni/postamble inutili. Pochi emoji, solo se richiesti.
- Codice, comandi, path e identificativi tecnici sempre in inglese.
- Per task di learning: privilegia la spiegazione del *perché* prima del *come*.

## Stack

- **OS host**: NixOS 25.11 (baremetal, no Proxmox)
- **File system**: ZFS (Disko per partizionamento dichiarativo)
- **IaC**: flake NixOS (Nix language, unica fonte di verità)
- **Config Management**: moduli NixOS + nixos-rebuild
- **Container Orchestration**: k3s (single-node, servizio host)
- **CNI**: Flannel (bundled k3s, default)
- **CI/CD**: GitHub Actions + Flux CD v2 (GitOps)
- **Secrets**: SOPS + age (sops-nix per host, Flux SOPS per k8s)
- **DNS**: Technitium DNS (modulo NixOS nativo)
- **Ingress**: Traefik (HelmRelease Flux in k8s)
- **TLS**: Let's Encrypt (DNS-01 Cloudflare) + cert-manager
- **Backup**: rclone → Cloudflare R2 (in pausa, vedi §Servizi)

## Struttura

```
flake.nix          - Entry point NixOS (pin nixpkgs, nixpkgs-unstable, sops-nix, disko)
hosts/nebula/      - Config specifica del server: disko, hardware, networking,
                     impermanence, k3s, technitium, backup (in pausa), tailscale,
                     beszel-agent (servizi host)
hosts/taiga/       - Raspberry Pi 4 (Klipper + Moonraker + Mainsail)
hosts/installer/   - ISO NixOS headless per nixos-anywhere
modules/           - Moduli NixOS riusabili: common (utenti, SSH, sops), keys
secrets/           - Secret host cifrati con SOPS (*.enc.yaml)
k8s/               - Manifesti GitOps (Flux) — invariato dalla migrazione
docs/              - Documentazione step-by-step (roadmap, decisioni, migration)
.github/workflows/ - CI (nix flake check, kubeconform, gitleaks)
```

> **Regola di organizzazione**: i moduli tecnici (technitium, k3s, backup,
> tailscale, beszel-agent) vivono accanto al loro host in `hosts/<host>/`, non
> in `modules/`. `modules/` contiene solo helper *cross-host* (utenti, SSH,
> sops, keys). Quando un secondo host NixOS importerà uno di questi servizi, il
> modulo verrà **promosso** in `modules/` con opzioni (`mkOption` + `config`)
> per la riusabilità. Per Astra single-host questo refactor è YAGNI.

## Servizi (stato corrente)

Stato runtime dei servizi host `nebula`. Per i dettagli operativi di ogni
servizio vedi la doc specifica in `docs/0N-*.md`.

- **Technitium DNS** — attivo (`hosts/nebula/technitium.nix`)
- **k3s** — attivo (`hosts/nebula/k3s.nix`)
- **Flux CD** — attivo, sync ~10min (`k8s/clusters/dyson/`)
- **cert-manager + Traefik** — attivi, TLS wildcard Let's Encrypt
- **SOPS + age** — attivo, secret host e k8s cifrati
- **Tailscale** — attivo, subnet router 192.168.178.0/24 (S15b)
- **Beszel agent** — attivo, monitoring host (`hosts/nebula/beszel-agent.nix`)
- **Backup rclone → R2** — ⏸️ **in pausa** dal 2026-07-19, `hosts/nebula/backup.nix` commentato in `default.nix` (vedi `docs/03-backup.md` per procedura di riattivazione)

## Network

Schema rete canonico (topologia, IP, bridge, firewall, dominio, VLAN target)
→ [docs/01-network.md](docs/01-network.md).

## Guardrail operativi

### 🔴 Zona rossa — mostrare e aspettare conferma

```
Rete:        qualsiasi chiamata HTTP reale (API, scraping, download)
Secrets:     plaintext mai in repo (SOPS + age obbligatorio)
File dati:   scrittura su secrets/ (cifrati), *.enc.yaml, .sops.yaml
NixOS:       nixos-rebuild switch/boot su host remoto (scrive /nix/var/nix/profiles)
K8s:         kubectl apply/delete (modifica cluster)
SOPS:        sops --encrypt (modifica file cifrati)
```

Pattern obbligatorio prima di procedere:
```
Sto per eseguire:
  [tipo]: [dettaglio esatto — URL, comando, path]
  Scopo: [perché è necessario]
  Impatto: [cosa cambia/scrive/modifica]

Attendo conferma prima di procedere.
```

### 🟢 Zona verde — procedere autonomamente

- Leggere qualsiasi file di codice/config/docs
- Scrivere/modificare codice in `hosts/`, `modules/`, `k8s/`, `docs/`
- Eseguire `nix flake check`, `kubeconform`, `gitleaks`
- `git add <file specifici>` (proporre commit, attendere conferma — vedi §Regole di commit)

### Errori in esecuzione

Quando uno script va in errore:
1. Fermarsi immediatamente — non tentare fix autonomi, non ritentare varianti
2. Mostrare l'errore esattamente com'è (output completo)
3. Aspettare istruzioni

Non fare reverse engineering autonomo su API o sistemi esterni quando uno script fallisce.

## Regole di commit

Formato: `<tipo>(<scope>): <descrizione>`

**Scope per layer:**

| Scope       | Quando usarlo                              |
|-------------|--------------------------------------------|
| `nix`       | Modifiche a flake.nix, hosts/, modules/    |
| `k8s`       | Manifesti Kubernetes, Helm chart, Flux     |
| `ci`        | GitHub Actions workflow                    |
| `docs`      | File in `docs/`                            |

**Esempi:**
```
feat(nix): add technitium-dns-server module
fix(k8s): correct cilium helm release values
chore(ci): add nix flake check job
docs: add nixos migration guide
```

Lo scope è opzionale per modifiche trasversali (es. rinomina globale,
refactor struttura repo).

**Override di questo repo:**

- **Lingua messaggio: italiano** (codice e documentazione in inglese, messaggi di commit in italiano)
- **Commit**: l'agente può committare dopo aver proposto (messaggio + stat). Nessuna
  attesa di conferma esplicita per il commit stesso.
- **Push**: mai dall'agente
- **Hook fail**: niente `--no-verify`; stop + mostra errore

### Proporre commit a fine task

Trigger: task completato con `nix flake check` verde; aggiornamento `docs/roadmap.md` o `docs/0N-*.md`; milestone intermedia stabile (schema Nix, primo servizio funzionante). Preferire commit atomici (un task = un commit; se ha sotto-step, un commit per sotto-step).

## Procedure di sync (matrice evento → write primario)

**Regola anti-fanout** (la più importante):

- storia → `CHANGELOG.md` (futuro, se versioning prodotto)
- perché → `docs/decisions.md` / `docs/stack-decisions.md`
- workaround vivo → `docs/known_issues.md` (futuro)
- coda/next → `docs/roadmap.md`
- contratto → `docs/contract.md` (futuro)
- istruzioni agenti → questo file

Mai copiare la stessa tabella in due file.

| Evento | Obbligatorio | Condizionale (solo se…) |
|---|---|---|
| Modifica NixOS (`flake.nix`/`hosts/`/`modules/`) | i file NixOS toccati | `docs/0N-*.md` se cambia procedura operativa; `stack-decisions.md` se nuova scelta architetturale |
| Modifica manifest k8s | `k8s/` file toccati | `roadmap.md` se chiude/aggiunge sprint; `0N-*.md` se cambia procedura |
| Sprint completato | `roadmap.md` (riga sprint → ✅) | `README.md` §Fasi + `docs/README.md` mappa doc; `0N-*.md` se la doc Sprint era il DoD |
| Nuova decisione architetturale | append `D-NNN` in `stack-decisions.md` | `AGENTS.md` §Stack solo se cambia invariante stack |
| Toggle backup (pausa/riprendi) | `AGENTS.md` §Servizi + `docs/03-backup.md` | `README.md` §Stack se cambia layer Backup; `roadmap.md` S6 |
| Rotazione secret | `docs/06-secrets-sops.md` (procedura) | `secrets/*.enc.yaml` aggiornato (conferma obbligatoria) |
| Nuovo argomento doc | `docs/0N-*.md` + `docs/README.md` (indice) | `AGENTS.md` se cambia modalità di lavoro |
| doc-only | il file toccato | niente altro |

**Anti-pattern**: NON aggiornare `README.md` / `PRODUCT.md` / `DESIGN.md` salvo trigger esplicito (cambia UX repo, identità prodotto, design system). Il fan-out a 7 file per ogni feature è il principale fonte di drift.

## Come lavorare

1. **Leggere `docs/roadmap.md` e §Servizi** a inizio sessione
2. **Risposte dirette, senza preambolo** — niente "Certo! Ecco come possiamo procedere..."
3. **Un task alla volta** — non saltare avanti se ci sono dipendenze non risolte
4. **Fermarsi sui punti aperti** — non inventare valori per soglie, coordinate, endpoint non testati. Segnalare e proporre un default. Aspettare conferma se bloccante.
5. **Test prima di considerare completato** — `nix flake check` happy path + edge case principale
6. **Codice tipato** — type hints Python, type annotations Nix; mypy/flake check deve passare
7. **Aggiornare workaround/KI** se scoperti (file canonico della matrice)
8. **Suggerire aggiornamento roadmap/status** a fine sessione
9. Non assumere ambiente pulito — verifica prima di nuove feature
10. **Protocollo fine sessione** — riepilogo breve (3-5 righe) in 3 punti: **Fatto** (file, commit, tag) · **Non fatto / Bloccato** (cosa è rimasto e perché) · **Prossimo suggerito** (un passo logico). Non ripetere dettagli già nel commit o nel codice.

### Spiegazione obbligatoria prima di modificare file

Per ogni modifica non banale a qualsiasi file del progetto (codice, docs,
config YAML, README), spiegare e **aspettare conferma**:

1. **Cosa cambia** — il problema tecnico concreto che la modifica risolve (non astratto)
2. **Come** — le scelte implementative rilevanti: cosa hai considerato, cosa hai scartato e perché
3. **Impatto** — cosa cambia per chi legge o modifica il codice dopo

L'obiettivo non è validare la scelta, ma permettere all'utente di capire,
valutare e mantenere il codice in autonomia.

**Eccezioni** (procedere direttamente): fix banali (typo, 1-2 righe senza
effetti collaterali); istruzione esplicita "vai"/"implementa direttamente";
correzioni lint/mypy/test che non cambiano semantica; `docs/known_issues.md`
e `docs/status.md` a fine sessione (routine — ma comunicare cosa si scrive
prima di farlo).

## Comandi utili

```bash
# Build/apply NixOS (da workstation, contro nebula remoto)
nix flake check
# Workstation NixOS:
nixos-rebuild switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo
# Workstation WSL/macOS:
nix run nixpkgs#nixos-rebuild -- switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo

# k3s (via SSH su nebula)
ssh cosimo@192.168.178.2
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A

# Flux
k3s flux get kustomizations
k3s flux get helmreleases -A

# SOPS
sops --encrypt --in-place secrets/foo.enc.yaml
sops --decrypt secrets/foo.enc.yaml
```

### Variabili d'ambiente rilevanti

| Variabile | Default prod | Note |
|---|---|---|
| `HEALTHCHECKS_URL` | non impostata (ping skip) | Dead-man switch per job cron |

## Tool e workflow

- Preferisci `read`/`grep`/`glob` prima di lanciare comandi costosi.
- Per task ripetuti, valutare la creazione di un custom command (`.opencode/commands/`).
- Per task specializzati (review NixOS config, check manifest k8s), valutare un subagent dedicato (`.opencode/agents/`).
- Se trovi un pattern ricorrente del progetto, proporre una skill (`.opencode/skills/`).
- `nix flake check` e `nixos-rebuild` chiedono conferma per `switch`/`boot`.
- `kubectl apply/delete` chiedono sempre conferma.
- `sops --encrypt` chiede conferma (modifica file).

## Sicurezza & secrets

- Non leggere, stampare o inviare al provider LLM il contenuto di file con
  secrets (`.env`, `*vault*`, `*secret*`, `*credential*`, `*.pem`, `*.key`,
  `**/.ssh/**`, `**/.aws/**`, `secrets/*.enc.yaml` non decifrati).
- **SOPS + age** per i secrets in repo (`.sops.yaml`). Mai committare plaintext.
- Non proporre soluzioni che richiedano `sudo` se non strettamente necessario.
- Se l'utente condivide un secret per errore, avvisalo immediatamente e
  consiglia rotazione.
- Per gestire l'host NixOS (nebula), operare via SSH da workstation come `cosimo` (sudo nopasswd via `wheel`).
  Per applicare config: `nixos-rebuild switch --flake .#nebula --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo`
  (su workstation non-NixOS: `nix run nixpkgs#nixos-rebuild -- switch --flake .#nebula --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo`).
  `--use-remote-sudo` è necessario: senza, nixos-rebuild fallisce con `Permission denied` su `/nix/var/nix/profiles/` perché prova a scrivere il system profile come utente non-root.
  L'install iniziale richiede `root@192.168.178.2` via nixos-anywhere (vedi `docs/00-nixos-installation.md`).
