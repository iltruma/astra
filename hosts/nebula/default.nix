# nebula — top-level NixOS config for Dell Optiplex 3050
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./disko.nix
    #./backup.nix
    ./impermanence.nix
    ./k3s.nix
    ./technitium.nix
    ./beszel-agent.nix
    ./tailscale.nix
    ../../modules/common.nix
  ];

  system.stateVersion = "25.11"; # NON modificare dopo il primo install

  console.keyMap = "it";

  nix = {
    settings = {
      auto-optimise-store = true;
      substituters = [ "https://cache.nixos.org/" ];
      trusted-users = [ "root" "cosimo" ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  documentation.enable = false;

  # Sostituisce `kubectl get` ripetuti, lanciato da SSH con `k9s`.
  environment.systemPackages = [ pkgs.k9s ];

  # k3s scrive il kubeconfig in /etc/rancher/k3s/k3s.yaml (mode 0644, vedi k3s.nix).
  # Senza questo, k9s fallisce con "Plugins load failed!" perché ~/.kube/config non esiste.
  environment.sessionVariables = {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
