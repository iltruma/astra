{ config, lib, pkgs, unstable, ... }:

# ----------------------------------------------------------------------------
# Technitium DNS — modulo NixOS + configurazione manuale
# ----------------------------------------------------------------------------
# Questo modulo copre il "come" (binario, firewall, porte). Le impostazioni
# "cosa" (zone, blocklist, nome server) si configurano dalla web UI
# (https://dns.lab.paroparo.it) e vivono nello stato persistente su ZFS
# (/var/lib/technitium-dns-server/): sopravvivono a nixos-rebuild e reinstall.
#
# Checklist configurazione manuale (UI, una tantum dopo primo boot):
#
#   1. SERVER DOMAIN
#      Settings → General → "DNS Server Domain" → impostare a "sentinel"
#      (coerente con la roadmap). Cosmetico, nessun impatto funzionale.
#
#   2. ZONA lab.paroparo.it
#      Zones → "lab.paroparo.it" (Primary Zone). I record da creare sono
#      dichiarati in:
#        ../dns-zone.lab.paroparo.it
#      Formato BIND zone file, importabile via UI o API. Record chiave:
#      - apex A → 192.168.178.2
#      - wildcard *.lab.paroparo.it A → 192.168.178.2
#      - ns1 A → 192.168.178.2 + NS delegation
#      - servizi espliciti: dns, uptime, homepage, beszel, iris
#
#   3. BLOCKING (ads + tracker + malware)
#      Settings → Blocking → "Enable Blocking" ON, "Blocking Type" NX Domain.
#      Le blocklist da incollare in "Allow / Block List URLs" sono in:
#        ../dns-blocklists.txt
#      Tre liste di qualità (HaGeZi Pro, Steven Black, AdGuard DNS filter),
#      auto-update ogni 24h.
#
#   4. RECURSION + DNSSEC (best practice per privacy)
#      Settings → Recursion → "Use Recursion" ON, "Enable DNSSEC Validation"
#      ON, "Allow Recursion" → "Only For Private Networks" (default).
#      Settings → Proxy & Forwarders → lasciare Cloudflare/Google come
#      fallback (forwarder DoH già cifrato).
#
#   5. (Opzionale) QUERY LOGS SQLite
#      Apps → installa "Query Logs (SQLite)", retention 7 giorni.
#
# Verifiche post-configurazione:
#   - dig @192.168.178.2 homepage.lab.paroparo.it → 192.168.178.2
#   - dig @192.168.178.2 doubleclick.net          → NXDOMAIN
#   - dig @192.168.178.2 +dnssec example.com      → "ad" bit set
# ----------------------------------------------------------------------------

{
  services.technitium-dns-server = {
    enable = true;
    package = unstable.technitium-dns-server;  # nixpkgs-unstable (15.x), vedi flake.nix
    # Gestisco il firewall manualmente per:
    # - 53 UDP/TCP: DNS, aperto per la LAN
    # - 53443 (HTTPS web UI): NON aperto — l'unico accesso è via
    #   Traefik reverse proxy su dns.lab.paroparo.it (443 → 5380)
    # - 5380 (HTTP web UI): aperto SOLO per loopback, per Traefik in
    #   hostNetwork che gira sullo stesso host
    openFirewall = false;
  };

  networking.firewall = {
    allowedUDPPorts = [ 53 ];   # DNS UDP
    allowedTCPPorts = [ 53 ];   # DNS TCP
    # 5380 (Technitium web UI HTTP): solo per loopback.
    # Traefik gira in hostNetwork su nebula, quindi quando accede a
    # 192.168.178.2:5380 il traffico attraversa l'interfaccia lo e
    # questa regola matcha. Client LAN vengono droppati.
    extraInputRules = ''
      -A INPUT -i lo -p tcp --dport 5380 -j ACCEPT
    '';
  };
}
