# Klipper + Moonraker + Mainsail with Let's Encrypt (DNS-01 Cloudflare)
{ config, lib, pkgs, ... }:

{
  services.klipper = {
    enable = true;
    mutableConfig = true;

    configFile = lib.mkIf (builtins.pathExists ./printer.cfg)
      ./printer.cfg;

    settings = lib.mkIf (!(builtins.pathExists ./printer.cfg)) {
      printer = {
        kinematics = "setta il giusto printer.cfg";
        max_velocity = 0;
        max_accel = 0;
      };
    };
  };

  services.moonraker = {
    enable = true;
    address = "0.0.0.0";

    settings = {
      authorization = {
        trusted_clients = [
          "127.0.0.0/8"
          "192.168.178.0/24"
        ];
        cors_domains = [
          "https://taiga.lab.paroparo.it"
          "http://192.168.178.43"
        ];
      };
    };
    allowSystemControl = true;
  };

  services.mainsail = {
    enable = true;
    hostName = "taiga.lab.paroparo.it";

    nginx = {
      forceSSL = true;
      sslCertificate = "${config.security.acme.certs."taiga.lab.paroparo.it".directory}/chain.pem";
      sslCertificateKey = "${config.security.acme.certs."taiga.lab.paroparo.it".directory}/key.pem";
      # enableACME omesso: confligge con dnsProvider (richiede webroot)
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "casini.cosimo@gmail.com";

    certs."taiga.lab.paroparo.it" = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."taiga/cloudflare-acme-env".path;
      group = "nginx";
    };
  };

  sops.secrets."taiga/cloudflare-acme-env" = {
    sopsFile = ../../secrets/taiga-cloudflare-acme.enc.yaml;
    format = "yaml";
  };

  security.polkit.enable = true;   # richiesto da moonraker.allowSystemControl

  users.groups.dialout = { };  # accesso seriale MCU
}
