# # hosts/nebula/technitium.nix
#
# Technitium DNS server come servizio NixOS nativo.
# Modulo NixOS ufficiale in nixpkgs: services.technitium-dns-server (v15.2.0).
#
# Configurazione:
#   - Ascolta su 0.0.0.0:53 (UDP/TCP) — risolve per la LAN 192.168.178.0/24
#   - State in /var/lib/technitium-dns-server (StateDirectory)
#   - Hardened: DynamicUser, NoNewPrivileges, ProtectSystem=strict

{ config, lib, pkgs, ... }:

{
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;  # apre 53 UDP/TCP, 5380, 53443
  };
}
