{ config, lib, pkgs, ... }:

{
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;  # apre 53 UDP/TCP, 5380, 53443
  };
}
