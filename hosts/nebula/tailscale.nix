{ config, lib, pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    # Auth key letto da /run/secrets (SOPS lo popola al boot, prima di tailscaled)
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
    # "server" = abilita IP forwarding + annuncio subnet route
    useRoutingFeatures = "server";
    # Flag dichiarativi passati a `tailscale up` (equivalente di `tailscale up --advertise-routes=...`)
    extraUpFlags = [
      "--advertise-routes=192.168.178.0/24"
      "--accept-routes"
    ];
  };

  # SOPS: dove trovare il file cifrato con la auth key
  sops.secrets."tailscale/auth-key" = {
    sopsFile = ../../secrets/tailscale-auth.enc.yaml;
  };


  # Porta wireguard di Tailscale (necessaria per i client Tailscale che arrivano da Internet)
  # 41641/UDP. Di default NixOS non la apre.
  networking.firewall.allowedUDPPorts = [ 41641 ];
}