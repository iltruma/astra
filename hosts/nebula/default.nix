{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./disko.nix
    ./backup.nix
    ./impermanence.nix
    ./k3s.nix
    ./technitium.nix
    ./beszel-agent.nix
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
}
