# modules/common.nix
#
# Configurazione comune a tutti gli host NixOS del repo.
# Importato automaticamente da modules/default.nix.
#
# Contiene:
#   - Utenti (cosimo, con sudo + SSH)
#   - SSH server hardening
#   - sops-nix config (convergenza con Flux SOPS esistente)
#   - Timezone e locale
#   - Pacchetti CLI essenziali

{ config, lib, pkgs, ... }:

{
  # ── Utente cosimo ────────────────────────────────────────────────────────────
  users.users.cosimo = {
    isNormalUser = true;
    description = "Cosimo Casini";
    extraGroups = [ "wheel" ];  # sudo
    openssh.authorizedKeys.keys = import ./keys.nix;
  };

  # Sudo senza password per il gruppo wheel (comodo per single-user homelab)
  security.sudo.wheelNeedsPassword = false;

  # ── SSH server hardening ─────────────────────────────────────────────────────
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

  # ── SOPS-nix: secrets host cifrati con la stessa chiave age di Flux ──────────
  # Aggiungi sops.secrets.<name>.sopsFile = ../secrets/<name>.enc.yaml
  # man mano che i moduli servizio ne hanno bisogno (k3s.nix, backup.nix già li hanno).
  sops.age.keyFile = "/persist/sops/age/keys.txt";
  # Disabilita l'auto-import delle SSH host keys di NixOS come GPG/age
  # (sennò sops-install-secrets prova a usarle e fallisce la decifratura)
  sops.gnupg.sshKeyPaths = [ ];
  sops.age.sshKeyPaths = [ ];

  # ── Timezone e locale ────────────────────────────────────────────────────────
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";

  # ── Pacchetti comuni (CLI essenziali per gestione host) ─────────────────────
  environment.systemPackages = with pkgs; [
    vim
    curl wget
    git
    htop
    jq
    tmux
  ];

  # ── Nix: abilita flakes globalmente ─────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
