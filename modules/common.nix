# Shared: user, SSH, SOPS, locale, base packages
{ config, lib, pkgs, ... }:

{
  users.users.cosimo = {
    isNormalUser = true;
    description = "Cosimo Casini";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = import ./keys.nix;
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = true;
    hostKeys = [
      { type = "ed25519"; path = "/persist/etc/ssh/ssh_host_ed25519_key"; }
    ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      X11Forwarding = false;
      KbdInteractiveAuthentication = false;
    };
  };

  sops.age.keyFile = "/persist/sops/age/keys.txt";
  # Disabilita import SSH host keys come age/GPG: causerebbe errori in sops-install-secrets
  sops.gnupg.sshKeyPaths = [ ];
  sops.age.sshKeyPaths = [ ];

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";

  environment.systemPackages = with pkgs; [
    vim
    curl wget
    git
    htop
    jq
    tmux
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
