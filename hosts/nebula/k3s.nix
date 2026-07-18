{ config, lib, pkgs, ... }:

{
  services.k3s = {
    enable = true;
    role = "server";

    extraFlags = toString [
      "--disable=traefik"              # gestito da Flux
      "--disable=servicelb"
      "--disable=local-storage"        # ZFS fornisce storage locale
      "--disable=metrics-server"       # Beszel copre monitoring
      "--write-kubeconfig-mode=0644"
    ];

    # Override del ConfigMap bundled: delega a Technitium per lab.paroparo.it.
    # services.k3s.manifests piazza il file in /var/lib/rancher/k3s/server/manifests/
    # e lo applica al boot; il nome "coredns" è richiesto da k3s.
    # Namespace flux-system: k3s non crea namespace implicitamente quando applica
    # i manifest in server/manifests/, quindi va materializzato prima dei Secret.
    # Naming: "flux-namespace" < "flux-secret-*" (n < s) → ordine lessicale garantito.
    manifests."flux-namespace" = {
      content = {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "flux-system";
      };
    };
    manifests."coredns-custom" = {
      content = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "coredns";
          namespace = "kube-system";
        };
        data = {
          Corefile = ''
            .:53 {
                errors
                health
                ready
                kubernetes cluster.local in-addr.arpa ip6.arpa {
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                }
                forward . 192.168.178.2:53
                cache 30
                loop
                reload
                loadbalance
            }
            lab.paroparo.it:53 {
                errors
                cache 30
                forward . 192.168.178.2:53
            }
          '';
        };
      };
    };
  };

  sops.secrets = {
    "k3s/flux-git-auth" = {
      sopsFile = ../../secrets/flux-git-auth.enc.yaml;
      format = "yaml";
    };
    "k3s/flux-sops-age" = {
      sopsFile = ../../secrets/flux-sops-age.enc.yaml;
      format = "yaml";
    };
  };

  # Symlink dei secret Flux in manifests/ prima che k3s parta
  systemd.tmpfiles.rules = [
    "d /var/lib/rancher/k3s/server/manifests 0755 root root - -"
    "L+ /var/lib/rancher/k3s/server/manifests/flux-secret-git-auth.yaml - - - - /run/secrets/k3s/flux-git-auth"
    "L+ /var/lib/rancher/k3s/server/manifests/flux-secret-sops-age.yaml - - - - /run/secrets/k3s/flux-sops-age"
  ];

  networking.firewall.allowedTCPPorts = [ 10250 ]; # kubelet API

  environment.systemPackages = with pkgs; [ k3s ];
}
