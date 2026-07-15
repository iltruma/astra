# modules/keys.nix
#
# Chiavi SSH autorizzate per cosimo.
# Usato da:
#   - modules/common.nix  (utente cosimo sul sistema installato)
#   - hosts/installer/    (root sull'ISO installer)
#
# Per aggiornare la chiave: modifica solo questo file.

[
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHRFFsFLz9/OeeBA6HLgCvVxjbUgUERbMNaj7vAzRx7p casini.cosimo@gmail.com"
]
