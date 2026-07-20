# taiga hardware: RPi4, kernel, filesystem, zram
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;

  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci" "usbhid" "usb_storage"
  ];
  boot.kernelModules = [
    "i2c-dev"   # I2C (display, sensori)
    "spi-dev"   # SPI (ADXL345 input shaper)
  ];

  # da verificare: lsblk sul Pi per confermare il label
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];
}
