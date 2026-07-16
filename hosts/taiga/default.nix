{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./klipper.nix
    ../../modules/common.nix
  ];

  system.stateVersion = "25.11";
}
