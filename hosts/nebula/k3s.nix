# # hosts/nebula/k3s.nix
#
# k3s single-node server con Flannel (CNI default).
#
# Flannel è il CNI bundled di k3s: funziona out of the box, nessun bootstrap
# dance. Cilium potrà essere aggiunto via Flux in un secondo momento quando
# il cluster è stabile e si vuole esplorare networking avanzato (eBPF, Hubble).
#
# Servizi disabilitati dal bundled k3s:
#   - traefik:        gestito da Flux in k8s/infra/traefik/
#   - servicelb:      non serve su single-node
#   - local-storage:  non serve, abbiamo /var/lib/rancher/k3s su ZFS
#   - metrics-server: non serve (Beszel copre il monitoring)
#
# Servizi mantenuti (default k3s):
#   - flannel:   CNI di default, semplice e robusto
#   - coredns:   Service discovery k8s (con ConfigMap custom per Technitium)
#   - kube-proxy: gestione Service IP

{ config, lib, pkgs, ... }:

{
  # ── k3s: abilitazione e configurazione ───────────────────────────────────────
  services.k3s = {
    enable = true;
    role = "server";

    extraFlags = toString [
      "--disable=traefik"              # Traefik via Flux
      "--disable=servicelb"            # non serve su single-node
      "--disable=local-storage"        # ZFS fornisce storage locale
      "--disable=metrics-server"       # Beszel copre monitoring
      "--write-kubeconfig-mode=0644"   # kubeconfig leggibile da utente non-root
    ];

    # ── CoreDNS custom: delega a Technitium per la zona lab.paroparo.it ───────
    # Override del ConfigMap bundled: nome esatto "coredns" richiesto da k3s.
    # services.k3s.manifests piazza il YAML in /var/lib/rancher/k3s/server/manifests/
    # e lo applica automaticamente al boot.
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

  # ── sops-nix: secret per Flux bootstrap ──────────────────────────────────────
  # Flux ha bisogno di:
  #   - flux-git-auth:  SSH key per pull dal repo GitHub
  #   - flux-sops-age:  chiave age per decifrare i *.enc.yaml
  # k3s li applica come manifest al boot, PRIMA che Flux parta.
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

  # ── Systemd tmpfiles: symlink dei secret Flux in manifests/ ──────────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/rancher/k3s/server/manifests 0755 root root - -"
    "L+ /var/lib/rancher/k3s/server/manifests/00-flux-git-auth.yaml - - - - /run/secrets/k3s/flux-git-auth"
    "L+ /var/lib/rancher/k3s/server/manifests/00-flux-sops-age.yaml - - - - /run/secrets/k3s/flux-sops-age"
  ];

  # ── Firewall ─────────────────────────────────────────────────────────────────
  # 6443 è già aperto in networking.nix.
  networking.firewall.allowedTCPPorts = [
    10250  # kubelet API (metrics)
  ];

  # ── Pacchetti CLI per gestione k8s ──────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    k3s  # include kubectl, crictl, ecc.
  ];
}
