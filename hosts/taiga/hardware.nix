# hosts/taiga/hardware.nix
#
# Hardware-specific per Raspberry Pi 4 Model B.
# aarch64-linux, boot da SD card, kernel rpi4.
#
# nixos-hardware fornisce overlay device tree e tuning specifici per Pi 4:
#   - GPU memory split
#   - Device tree overlays
#   - Firmware EEPROM management
#
# Build da workstation (non sul Pi):
#   nixos-rebuild switch --flake .#taiga \
#     --target-host pi@192.168.178.43 \
#     --build-host localhost
#
# Prerequisito sulla workstation (cross-compile aarch64):
#   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    # nixos-hardware: overlay e tuning specifici Pi 4
    # Aggiunto come input nel flake, fornisce driver e device tree corretti
  ];

  # ── CPU / architettura ───────────────────────────────────────────────────────
  nixpkgs.hostPlatform = "aarch64-linux";

  # ── Kernel: rpi4 con patch upstream ─────────────────────────────────────────
  # Il kernel rpi4 include i driver per GPIO, UART seriale, i2c, SPI
  # necessari per comunicare con la scheda stampante (es. SKR, Octopus)
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;

  # ── Boot: extlinux (U-Boot su Pi 4, no GRUB) ────────────────────────────────
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  # ── Moduli kernel per boot e periferiche ────────────────────────────────────
  boot.initrd.availableKernelModules = [
    "xhci_pci" "usbhid" "usb_storage"
  ];
  boot.kernelModules = [
    "i2c-dev"   # I2C (display, sensori)
    "spi-dev"   # SPI (ADXL345 per input shaper)
  ];

  # ── Filesystem: root su SD card ─────────────────────────────────────────────
  # da verificare: `lsblk` sul Pi per confermare il label
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # ── RAM: zram swap per evitare OOM durante nixos-rebuild sul Pi ──────────────
  # Anche se si builda dalla workstation, tenerlo come safety net
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # ── Hardware redistribuibile (firmware WiFi, BT) ─────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # ── Firmware EEPROM: aggiornamenti bootloader Pi 4 ──────────────────────────
  hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];
}
