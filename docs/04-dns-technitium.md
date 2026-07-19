# DNS — Technitium

Servizio DNS autorevole + ricorsivo, basato su [Technitium](https://technitium.com/dns/).
Nel setup NixOS gira come servizio nativo (modulo `services.technitium-dns-server`,
pacchetto da `nixpkgs-unstable` via `specialArgs.unstable`), non più come LXC separato.

## Perché Technitium (e non Pi-hole o AdGuard)

| Funzionalità               | Pi-hole v6 | AdGuard Home | **Technitium DNS** |
|----------------------------|-----------|--------------|--------------------|
| Zona autoritativa          | ❌        | ❌           | ✅ nativa          |
| Wildcard DNS               | ❌        | ❌           | ✅                 |
| Split horizon              | ❌        | ❌           | ✅ nativo          |
| DoH/DoT built-in           | ❌        | ✅           | ✅                 |
| Clustering                 | ❌        | ❌           | ✅ (v14+)          |
| RAM idle                   | ~50 MB    | ~50 MB       | ~150 MB            |
| Pacchetto nixpkgs          | ❌        | ✅           | ✅ (15.x da nixpkgs-unstable) |
| Modulo NixOS               | ❌        | ❌           | ✅                 |

Technitium è l'unica opzione che supporta nativamente:
- Zona primaria autoritativa per `lab.paroparo.it` (split-horizon)
- Record wildcard `*.lab.paroparo.it → 192.168.178.2`
- DoH/DoT per query ricorsive
- Modulo NixOS pronto all'uso

## Configurazione NixOS

In [`hosts/nebula/technitium.nix`](../hosts/nebula/technitium.nix):

```nix
{ config, lib, pkgs, unstable, ... }:

{
  services.technitium-dns-server = {
    enable = true;
    # Pacchetto da nixpkgs-unstable (vedi flake.nix → specialArgs.unstable).
    # Il default in nixpkgs stable è più vecchio; unstable ha la 15.x.
    package = unstable.technitium-dns-server;
    # Firewall gestito manualmente sotto (53 + 5380 loopback).
    openFirewall = false;
  };

  networking.firewall = {
    allowedUDPPorts = [ 53 ];   # DNS UDP
    allowedTCPPorts = [ 53 ];   # DNS TCP
    # 5380 (Technitium web UI HTTP): solo loopback.
    # Traefik gira in hostNetwork su nebula, quindi quando accede a
    # 192.168.178.2:5380 il traffico attraversa l'interfaccia lo.
    # Client LAN vengono droppati. 53443 (HTTPS web UI) resta chiuso.
    extraInputRules = ''
      -A INPUT -i lo -p tcp --dport 5380 -j ACCEPT
    '';
  };
}
```

Questo abilita:
- Servizio systemd `technitium-dns-server` con `DynamicUser`, `NoNewPrivileges`,
  `ProtectSystem=strict`, `CAP_NET_BIND_SERVICE`
- State directory `/var/lib/technitium-dns-server` (ZFS dataset `tank/var`)
- Ascolto su `0.0.0.0:53` (UDP e TCP)
- Web UI HTTP su `0.0.0.0:5380` (raggiungibile solo da loopback → Traefik)
- Web UI HTTPS su `0.0.0.0:53443` (chiuso dal firewall, non usato)

> **Perché firewall custom**: il modulo NixOS di default apre 53/5380/53443
> sulla LAN. Su astra serve un setup più stretto: la web UI deve essere
> raggiungibile solo da Traefik (che gira in hostNetwork sullo stesso host
> → attraversa l'interfaccia `lo`), non dai client LAN. Quindi `openFirewall = false`
> + regole custom.

## Zone file (BIND)

I record DNS sono versionati in Git come zona BIND:
[`hosts/nebula/dns-zone.lab.paroparo.it`](../hosts/nebula/dns-zone.lab.paroparo.it)

Per importare in Technitium dopo un reinstall:
- *Zones → lab.paroparo.it → Import → seleziona il file*

Per aggiungere un nuovo servizio: aggiungi il record nel file e reimporta,
oppure aggiungilo dalla web UI (poi aggiorna il file nel repo per mantenerlo allineato).

## Configurazione via web UI

Dopo l'install NixOS e il primo boot, Technitium va configurato via web UI.
Accesso dalla workstation via SSH tunnel:

```bash
# Dalla workstation
ssh -L 5380:127.0.0.1:5380 cosimo@192.168.178.2
# Apri browser su http://127.0.0.1:5380
```

### Configurazione minima

1. **Zona autoritativa `lab.paroparo.it`**:
   - *Zones → Add Zone → Primary Zone*
   - Nome: `lab.paroparo.it`
   - Tipo: Primary
   - Salva

2. **Record wildcard**:
   - Apri la zona `lab.paroparo.it`
   - *Add Record → A*
   - Name: `*` (o vuoto per la root)
   - IPv4 Address: `192.168.178.2`
   - Salva

3. **Record esplicito per Taiga** (necessario per ACME DNS-01):
   - *Add Record → A*
   - Name: `taiga`
   - IPv4 Address: `192.168.178.43`
   - Salva
   - Il wildcard coprirebbe anche `taiga`, ma il record esplicito ha priorità
      e punta al Pi direttamente invece che a Traefik su Nebula.

4. **Upstream ricorsivi (DoH)**:
   - *Settings → DNS Client*
   - Add: `https://cloudflare-dns.com/dns-query` (Cloudflare 1.1.1.1)
   - Add: `https://dns.quad9.net/dns-query` (Quad9 9.9.9.9)
   - Disabilita UDP plain (forza DoH) per privacy

5. **Blocklist** (consigliato):
   - *Settings → Blocking* → Enable Blocking ON, Blocking Type NX Domain
   - In "Allow / Block List URLs" incollare le URL da
     [`hosts/nebula/dns-blocklists.txt`](../hosts/nebula/dns-blocklists.txt) —
     tre liste di qualità: HaGeZi Pro (~200k domini, basso tasso falsi positivi),
     Steven Black (classica consolidata), AdGuard DNS filter (copertura
     malware/tracker extra). Auto-update ogni 24h.
   - Verifica: `dig @192.168.178.2 doubleclick.net` deve restituire `NXDOMAIN`.

6. **Server Domain** (cosmetico):
   - *Settings → General* → "DNS Server Domain" → `sentinel`
   - Coerente con la roadmap, nessun impatto funzionale.

7. **Recursion + DNSSEC** (best practice per privacy):
   - *Settings → Recursion* → Use Recursion ON, Enable DNSSEC Validation ON
   - Allow Recursion → "Only For Private Networks" (già il default)
   - Upstream DoH: Cloudflare `https://cloudflare-dns.com/dns-query` + Quad9
     `https://dns.quad9.net/dns-query` (vedi punto 3 sopra)
   - Verifica DNSSEC: `dig @192.168.178.2 +dnssec example.com` deve mostrare
     il bit `ad` (authenticated data) nella risposta.

8. **Cache e TTL**:
   - Default vanno bene per astra
   - Cache: ~24h, TTL negativi: 5min

> **Perché DNSSEC + recursion esplicita**: Technitium di default fa recursion
> ma DNSSEC va attivato a mano. Senza DNSSEC validation, un attaccante
> sulla rete può falsificare risposte per domini non firmati. Con DNSSEC
> ON, Technitium rifiuta le risposte non autentiche per i domini firmati.

### Configurazione avanzata

- **Conditional forwarder**: per query `*.lan` o `*.local`, delega al router
  Fritz!Box (`192.168.178.1`)
- **Log**: abilita log query (utile per debug, attenzione a privacy)
- **Stats**: Technitium ha statistiche built-in (no Grafana necessario)

## Verifica

```bash
# Da un client sulla LAN
dig @192.168.178.2 lab.paroparo.it
# Deve risolvere dalla zona locale (NO upstream)

dig @192.168.178.2 uptime.lab.paroparo.it
# Wildcard → 192.168.178.2 (Traefik k3s)

dig @192.168.178.2 google.com
# Deve risolvere via upstream DoH (Cloudflare/Quad9)

# Verifica DNSSEC (bit "ad" deve essere presente)
dig @192.168.178.2 +dnssec example.com
# flags: ... ad (authenticated data)

# Verifica blocklist (NXDOMAIN per domini bloccati)
dig @192.168.178.2 doubleclick.net
# status: NXDOMAIN

# Verifica web UI via loopback (solo dopo aver impostato Server Domain)
dig @192.168.178.2 sentinel.lab.paroparo.it
# → 192.168.178.2 (record esplicito nella zona)
# Poi da workstation: ssh -L 5380:127.0.0.1:5380 cosimo@192.168.178.2
# Browser: http://127.0.0.1:5380
```

## Accesso web UI (DNS rebind-safe)

La web UI Technitium è su `0.0.0.0:5380` ma il firewall NixOS accetta il
traffico sulla porta **solo da loopback** (regola custom in
`hosts/nebula/technitium.nix`). Client LAN: droppati.

Due modi per raggiungerla:

1. **SSH tunnel** (manuale, una tantum per config iniziale):
   ```bash
   ssh -L 5380:127.0.0.1:5380 cosimo@192.168.178.2
   # Browser: http://127.0.0.1:5380
   ```

2. **Traefik reverse proxy** (consigliato, permanente):
   - Manifest in [`k8s/apps/technitium/technitium-expose.yaml`](../k8s/apps/technitium/technitium-expose.yaml)
   - Endpoint k8s su `192.168.178.2:5380` (Technitium host) via hostNetwork
   - Ingress: `dns.lab.paroparo.it` → certificato wildcard Let's Encrypt
   - Accesso da browser: `https://dns.lab.paroparo.it`
   - DNS rebind: Technitium risponde direttamente ai client LAN, senza passare
     dal Fritz!Box, quindi la rebind protection del router non interferisce
     (verificato in S3).

## Backup e restore

Lo state di Technitium vive in `/var/lib/technitium-dns-server`. Era incluso
nel backup rclone notturno (in pausa dal 2026-07-19, vedi
[03-backup.md](03-backup.md)).

Restore:
```bash
systemctl stop technitium-dns-server
rclone sync r2:nebula-backup/technitium/ /var/lib/technitium-dns-server/
systemctl start technitium-dns-server
```

## Monitoraggio

- Status: `systemctl status technitium-dns-server`
- Statistiche: web UI → Dashboard (query/sec, cache hit rate, ecc.)
- Log: `journalctl -u technitium-dns-server`

## Aggiornamento

Il pacchetto viene da `nixpkgs-unstable` (vedi `flake.nix` → input
`nixpkgs-unstable` e `specialArgs.unstable`).

```bash
# Aggiorna il pin di nixpkgs-unstable
nix flake update --commit nixpkgs-unstable
# Workstation NixOS:
nixos-rebuild switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo
# Workstation WSL/macOS:
nix run nixpkgs#nixos-rebuild -- switch --flake .#nebula \
  --target-host cosimo@192.168.178.2 --build-host localhost --use-remote-sudo
```

Technitium non richiede migrazioni di state: ogni release mantiene
compatibilità del file system in `/var/lib/technitium-dns-server`.

## Trade-off

- **Pro**: zona autoritativa + ricorsivo in un unico processo, DoH/DoT built-in,
  modulo NixOS ufficiale, ~150 MB RAM.
- **Contro**: progetto single-developer (Shreyas Zare), ~5k stars (vs Pi-hole
  ~48k). Rischio abbandono medio, ma GPL-3 forkabile.
- **Piano B**: se Technitium viene abbandonato, alternative con split-horizon
  sono scarse. Workaround: AdGuard Home + dnsmasq wildcard sul Fritz!Box.
