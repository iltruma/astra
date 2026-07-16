{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.rclone ];

  # Credenziali R2 in formato dotenv:
  #   RCLONE_CONFIG_R2_TYPE=s3
  #   RCLONE_CONFIG_R2_PROVIDER=Cloudflare
  #   RCLONE_CONFIG_R2_ACCESS_KEY_ID=xxx
  #   RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=xxx
  #   RCLONE_CONFIG_R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
  sops.secrets."backup/rclone-env" = {
    sopsFile = ../../secrets/rclone-env.enc.yaml;
    format = "yaml";
  };

  systemd.services.rclone-backup = {
    description = "Backup off-site to Cloudflare R2";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.secrets."backup/rclone-env".path;
      ExecStart = pkgs.writeShellScript "rclone-backup" ''
        set -e
        R=${pkgs.rclone}/bin/rclone
        REMOTE=r2:nebula-backup

        $R sync /var/lib/technitium-dns-server $REMOTE/technitium/ --log-level INFO

        $R sync /var/lib/rancher/k3s $REMOTE/k3s/ \
          --exclude "agent/containerd/**" \
          --exclude "agent/run/**" \
          --exclude "data/**" \
          --log-level INFO

        $R sync /home $REMOTE/home/ \
          --exclude ".cache/**" \
          --exclude ".local/share/Trash/**" \
          --log-level INFO
      '';
    };
  };

  systemd.timers.rclone-backup = {
    description = "Schedule for rclone backup to R2";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;  # esegui al boot se il sistema era spento
      RandomizedDelaySec = "15min";
    };
  };
}
