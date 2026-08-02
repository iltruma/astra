# Astra Homelab — Agent Instructions

Regole per opencode quando lavora in questo repo. Questo file ha precedenza
su qualsiasi `CLAUDE.md` o impostazione globale.

> Per il setup globale di opencode (permission, MCP, provider) vedi
> `~/.config/opencode/opencode.jsonc`.

## Modalità di lavoro (IMPORTANTE)

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

## Tool e workflow

- Preferisci `read`/`grep`/`glob` prima di lanciare comandi costosi.
- Per task ripetuti, valutare la creazione di un custom command
  (`.opencode/commands/`).
- Per task specializzati (review NixOS config, check manifest k8s), valutare un
  subagent dedicato (`.opencode/agents/`).
- Se trovi un pattern ricorrente del progetto, proporre una skill
  (`.opencode/skills/`).
- `nix flake check` e `nixos-rebuild` chiedono conferma per `switch`/`boot`.
- `kubectl apply/delete` chiedono sempre conferma.
- `sops --encrypt` chiede conferma (modifica file).

## Progetto

Homelab su Dell Optiplex 3050 (i5-6500T, 16 GB RAM pianificato 32 GB, 500 GB SSD)
con **NixOS baremetal** (no hypervisor). k3s gira come servizio host, Technitium
DNS come servizio NixOS nativo.

## Stack

Vedi [README.md §Stack](../README.md#stack) per la tabella canonica completa
(11 voci). Motivazioni e tradeoff in [docs/stack-decisions.md](docs/stack-decisions.md).

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

## Commit naming convention

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

## Procedure di sync (matrice evento → write primario)

**Regola anti-fanout** (la più importante): ogni informazione ha **un solo file canonico**.
Gli altri file rimandano, non duplicano.

- **Stack tecnologico** → canonico in `README.md` §Stack
- **Schema rete / architettura** → canonico in `docs/01-network.md`
- **Stato servizi host** (incluso "backup in pausa") → canonico in `AGENTS.md` §Servizi
- **Decisioni architetturali** → canonico in `docs/stack-decisions.md`
- **Piano / sprint** → canonico in `docs/roadmap.md`
- **Argomenti operativi** → canonico in `docs/0N-*.md` (uno per argomento)
- **Regole agenti** → canonico in `AGENTS.md`

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

**Anti-pattern**: NON aggiornare `README.md` salvo trigger esplicito (cambia
quickstart / stack / architettura). NON duplicare una tabella in due file.

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

- Iris (gateway/router Fritz!Box): 192.168.178.1
- Nebula (NixOS host): 192.168.178.2
  - Servizi esposti: k3s API (.6443), DNS (.53), HTTP (.80), HTTPS (.443)
  - k3s gira come servizio sullo stesso host (no VM separata)
  - Technitium DNS gira come servizio NixOS (no LXC separato)
- Dominio: `lab.paroparo.it` (record locali in Technitium; host + servizi web via
  wildcard `*.lab.paroparo.it` → Traefik in k3s; TLS Let's Encrypt).
  Niente `.internal`.
