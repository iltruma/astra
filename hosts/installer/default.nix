# Headless NixOS installer ISO for nixos-anywhere bootstrap
{ modulesPath, lib, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # mkForce: installation-cd-minimal non avvia sshd di default
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  users.users.root.openssh.authorizedKeys.keys = import ../../modules/keys.nix;

  networking.useDHCP = false;
  networking.interfaces.enp1s0.ipv4.addresses = [
    {
      address = "192.168.178.2";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "192.168.178.1";
  networking.nameservers = [ "1.1.1.1" ];
}
