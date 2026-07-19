{ config, pkgs, ... }:

# ----------------------------------------------------------------------------
# Beszel agent — monitora le risorse di nebula (CPU, RAM, disco, rete) e le
# invia all'hub Beszel esposto in k3s (beszel.lab.paroparo.it).
# Modulo NixOS: services.beszel.agent (file upstream: nixos/modules/services/
# monitoring/beszel-agent.nix).
# ----------------------------------------------------------------------------

{
  services.beszel.agent = {
    enable = true;
    # Apre la porta TCP 45876 nel firewall NixOS, raggiungibile dall'hub
    # Beszel che gira come pod k3s sullo stesso host.
    openFirewall = true;
    # La enrollment key è letta dal file decifrato da sops al boot.
    # EnvironmentFile accetta il formato KEY=valore (env vars standard).
    environmentFile = config.sops.secrets."beszel/agent-key".path;
  };

  sops.secrets."beszel/agent-key" = {
    sopsFile = ../../secrets/beszel-agent-key.enc.yaml;
    format = "dotenv";
    # L'utente beszel-agent (creato dal modulo) deve poter leggere il file
    # per passarlo come EnvironmentFile a systemd.
    owner = "beszel-agent";
    group = "beszel-agent";
    mode = "0400";
  };
}