# Beszel agent — invia metriche host all'hub k3s (beszel.lab.paroparo.it)
{ config, pkgs, ... }:

{
  services.beszel.agent = {
    enable = true;
    openFirewall = true;
    environment.KEY_FILE = config.sops.secrets."beszel/agent-key".path;
    smartmon = {
      enable = true;
      deviceAllow = [ "/dev/sda" ];
    };
  };

  sops.secrets."beszel/agent-key" = {
    sopsFile = ../../secrets/beszel-agent-key.enc.yaml;
    format = "yaml";
    # beszel-agent (creato dal modulo) deve leggere il file per passarlo a systemd
    owner = "beszel-agent";
    group = "beszel-agent";
    mode = "0400";
  };
}