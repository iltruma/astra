# modules/klipper.nix
#
# Stack stampa 3D: Klipper + Moonraker + Mainsail.
# Usato da hosts/taiga.
#
# ── Architettura ────────────────────────────────────────────────────────────
#   Mainsail (nginx :80) → Moonraker (:7125) → Klipper (socket) → MCU
#
# ── mutableConfig = true ────────────────────────────────────────────────────
# printer.cfg è modificabile dalla UI Mainsail (calibrazioni, PID tuning,
# SAVE_CONFIG). NixOS inizializza il file se non esiste, ma non lo sovrascrive
# ad ogni rebuild. Le modifiche dalla UI sopravvivono.
#
# Quando vuoi "fotografare" lo stato corrente nel repo:
#   scp pi@192.168.178.43:/var/lib/klipper/printer.cfg \
#       hosts/taiga/printer.cfg
#   git add hosts/taiga/printer.cfg && git commit
#
# ── Porta seriale MCU ────────────────────────────────────────────────────────
# da verificare: ls /dev/serial/by-id/ sul Pi con la scheda collegata
# il path dipende dalla scheda (SKR, Octopus, ecc.)
#
# ── Flashing firmware MCU ────────────────────────────────────────────────────
# NixOS può buildare il firmware MCU ma il flashing è manuale (una tantum):
#   nix-shell -p klipper --run "make menuconfig"  # configura per la tua scheda
#   klipper-flash-<mcu>                            # se enableKlipperFlash = true
# Vedi: https://www.klipper3d.org/Installation.html#building-and-flashing-the-micro-controller

{ config, lib, pkgs, ... }:

{
  # ── Klipper ──────────────────────────────────────────────────────────────────
  services.klipper = {
    enable = true;

    # mutableConfig: printer.cfg è scrivibile dalla UI — non sovrascrivere
    # ponytail: false = dichiarativo puro (nixos-rebuild aggiorna il cfg)
    #           true  = UI può modificare (calibrazioni, SAVE_CONFIG)
    # Scelto true: la config stampante cambia spesso durante il tuning
    mutableConfig = true;

    # configFile: usato solo per inizializzare printer.cfg se non esiste.
    # Punta al file nel repo. Copialo da MainsailOS:
    #   scp pi@192.168.178.43:/var/lib/klipper/printer.cfg hosts/taiga/printer.cfg
    # ponytail: da verificare — placeholder finché non si migra la config reale
    configFile = lib.mkIf (builtins.pathExists ../../hosts/taiga/printer.cfg)
      ../../hosts/taiga/printer.cfg;

    # Porta seriale verso la scheda MCU — da verificare con:
    #   ls /dev/serial/by-id/
    # Esempio SKR Mini E3: /dev/serial/by-id/usb-Klipper_stm32g0b1xx_...
    # ponytail: da verificare al primo boot con la scheda collegata
    settings = lib.mkIf (!(builtins.pathExists ../../hosts/taiga/printer.cfg)) {
      # Placeholder minimo per avviare klipper senza printer.cfg nel repo.
      # Sostituire con la config reale o usare configFile.
      printer = {
        kinematics = "none";
        max_velocity = 300;
        max_accel = 3000;
      };
    };
  };

  # ── Moonraker ────────────────────────────────────────────────────────────────
  services.moonraker = {
    enable = true;
    address = "0.0.0.0";  # raggiungibile dalla LAN

    settings = {
      authorization = {
        # Permetti accesso dalla LAN senza token
        trusted_clients = [ "192.168.178.0/24" ];
        cors_domains = [
          "http://mainsail.lab.paroparo.it"
          "http://192.168.178.43"
        ];
      };

      # Disabilita system updates via UI (su NixOS si fa con nixos-rebuild)
      update_manager.enable_system_updates = false;
    };

    # Permette a Moonraker di fare reboot/restart servizi via UI
    allowSystemControl = true;
  };

  # ── Mainsail ─────────────────────────────────────────────────────────────────
  services.mainsail = {
    enable = true;
    hostName = "192.168.178.43";  # raggiungibile per IP dalla LAN
  };

  # ── polkit: richiesto da allowSystemControl ───────────────────────────────────
  security.polkit.enable = true;

  # ── Accesso seriale: klipper deve leggere /dev/ttyUSB* o /dev/ttyACM* ────────
  # Il gruppo dialout ha accesso alle porte seriali su Linux
  users.groups.dialout = { };
}
