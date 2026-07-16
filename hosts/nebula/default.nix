# hosts/nebula/default.nix
#
# Configurazione principale dell'host nebula (Dell Optiplex 3050).
# Aggrega: disko, hardware, networking + moduli host-specific + modules/common.nix
#
# Per buildare:
#   nix build .#nixosConfigurations.nebula.config.system.build.toplevel
#
# Per applicare:
#   nixos-rebuild switch --flake .#nebula
# (oppure --target-host root@192.168.178.2 per buildare in remoto)

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
    ../../modules/common.nix
  ];

  # ── system.stateVersion: NON modificare dopo il primo install ────────────────
  system.stateVersion = "25.11";

  # ── console: keyboard italiano ───────────────────────────────────────────────
  console.keyMap = "it";

  # ── Nix settings ────────────────────────────────────────────────────────────
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

  # ── Manciata di doc serve a zero se leggi i .md ────────────────────────────
  documentation.enable = false;
}
