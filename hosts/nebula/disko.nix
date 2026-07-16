{ lib, ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    };

    zpool = {
      tank = {
        type = "zpool";
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          mountpoint = "none";
        };
        options.ashift = "12"; # 4K sector (standard SSD)
        options.autotrim = "on";

        datasets = {
          "root" = {
            type = "zfs_fs";
            options.mountpoint = "/";
          };

          "nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
          };

          "var" = {
            type = "zfs_fs";
            options.mountpoint = "/var";
            mountpoint = "/var";
          };

          "home" = {
            type = "zfs_fs";
            options.mountpoint = "/home";
            mountpoint = "/home";
          };

          "persist" = {
            type = "zfs_fs";
            options.mountpoint = "/persist";
            mountpoint = "/persist";
          };

          "volumes" = {
            type = "zfs_fs";
            options.mountpoint = "/var/lib/rancher/k3s";
            mountpoint = "/var/lib/rancher/k3s";
          };
        };
      };
    };
  };

  # impermanence richiede neededForBoot = true per /persist e /var
  fileSystems."/persist" = {
    device = "tank/persist";
    fsType = "zfs";
    neededForBoot = true;
  };
  fileSystems."/var".neededForBoot = true;
}
