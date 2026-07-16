{ ... }:

{
  environment.persistence."/persist" = {
    hideMounts = true;

    files = [
      "/etc/machine-id"
    ];

    directories = [
      "/var/lib/nixos"  # UID/GID allocati da NixOS
      "/var/log"
      # /persist/sops/ usato direttamente da sops-nix (keyFile)
    ];
  };
}
