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

  # Dice a k9s/kubectl/flux dove trovare il kubeconfig di k3s. k3s lo scrive
  # in /etc/rancher/k3s/k3s.yaml con mode 0644 (vedi k3s.nix extraFlags).
  # Senza questo, k9s dà "Plugins load failed!" perché ~/.kube/config non esiste.
  environment.sessionVariables = {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
