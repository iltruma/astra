# nebula hardware: ZFS filesystems, boot, kernel modules
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.supportedFilesystems = [ "zfs" ];

  # mkDefault: disko può sovrascrivere (es. /boot da partlabel)
  fileSystems."/" = lib.mkDefault {
    device = "tank/root";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/nix" = lib.mkDefault {
    device = "tank/nix";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/var" = lib.mkDefault {
    device = "tank/var";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/home" = lib.mkDefault {
    device = "tank/home";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/persist" = lib.mkDefault {
    device = "tank/persist";
    fsType = "zfs";
    options = [ "zfsutil" ];
    neededForBoot = true;
  };

  fileSystems."/var/lib/rancher/k3s" = lib.mkDefault {
    device = "tank/volumes";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-id/ata-MicroFrom_512GB_SATA3_SSD_01312223B0788";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"
  ];
  boot.initrd.kernelModules = [ "zfs" ];
  boot.initrd.supportedFilesystems = [ "zfs" ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ip6_tables: richiesti da k3s/Flannel anche con IPv6 disabilitato
  boot.kernelModules = [
    "ip6_tables"
    "ip6table_mangle"
    "ip6table_raw"
    "ip6table_filter"
  ];

  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  boot.zfs.forceImportAll = true; # single-node, nessun altro host usa il pool

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ponytail: rigenerare al primo install (head -c4 /dev/urandom | od -A none -t x4)
  networking.hostId = "963e586d";
}
