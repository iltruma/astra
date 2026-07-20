# Tailscale VPN con subnet router per 192.168.178.0/24
{ config, lib, pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    # SOPS popola il file al boot, prima che tailscaled parta
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
    # "server" abilita IP forwarding e annuncio subnet route
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--advertise-routes=192.168.178.0/24"
      "--accept-routes"
    ];
  };

  sops.secrets."tailscale/auth-key" = {
    sopsFile = ../../secrets/tailscale-auth.enc.yaml;
  };

  networking.firewall.allowedUDPPorts = [ 41641 ]; # WireGuard port (Tailscale)
}
