# Technitium DNS server — configurazione UI/zone in docs/04-dns-technitium.md
{ config, lib, pkgs, unstable, ... }:

{
  services.technitium-dns-server = {
    enable = true;
    package = unstable.technitium-dns-server;  # nixpkgs-unstable (15.x), vedi flake.nix
    # openFirewall=false: gestiamo le porte manualmente sotto per controllare
    # che 5380 (web UI) sia accessibile solo in loopback (via Traefik), non dalla LAN.
    openFirewall = false;
  };

  networking.firewall = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
    # 5380 solo loopback: Traefik usa hostNetwork su nebula, il traffico
    # verso 192.168.178.2:5380 passa per lo — i client LAN vengono droppati.
    extraInputRules = ''
      -A INPUT -i lo -p tcp --dport 5380 -j ACCEPT
    '';
  };
}
