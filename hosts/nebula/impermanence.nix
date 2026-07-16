# # hosts/nebula/impermanence.nix
#
# Lista dichiarativa di cosa sopravvive ai reboot in /persist.
# Il modulo impermanence crea bind mount da /persist/<path> → /<path>.
#
# Filosofia: su NixOS il "rollback" è git revert + nixos-rebuild switch.
# Questo modulo non serve a tornare indietro, ma a dichiarare esplicitamente
# lo stato che non è ricostruibile dal flake:
#   - machine-id   (identità systemd, usata da journald e altri servizi)
#   - chiave SOPS  (già in /persist per sops-nix, qui la rendiamo esplicita)
#   - nixos state  (UID/GID allocati dinamicamente da NixOS)
#
# SSH host key: gestita direttamente in /persist via services.openssh.hostKeys
# (vedi common.nix) — nessun bind mount necessario, sshd legge da /persist diretto.
# Solo ed25519: RSA è legacy, non ha senso mantenerla su astra.
#
# Tutto il resto (Technitium, k3s, /var) vive su tank/var e tank/volumes
# che sono dataset ZFS separati e sopravvivono ai reboot indipendentemente.

{ ... }:

{
  environment.persistence."/persist" = {
    hideMounts = true;  # nasconde i bind mount da df/findmnt per pulizia output

    files = [
      "/etc/machine-id"
    ];

    directories = [
      "/var/lib/nixos"           # UID/GID allocati da NixOS (users, groups)
      "/var/log"                 # log di sistema (journald)
      # /persist/sops/ già usato da sops-nix (keyFile = "/persist/sops/age/keys.txt")
      # non serve dichiararlo qui: sops-nix lo gestisce direttamente
    ];
  };
}
