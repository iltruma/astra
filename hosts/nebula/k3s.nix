# k3s server + Flux bootstrap manifests
{ config, lib, pkgs, ... }:

{
  services.k3s = {
    enable = true;
    role = "server";

    # NON disabilitare servicelb (klipper-lb): Traefik Service type=LoadBalancer lo richiede
    extraFlags = toString [
      "--disable=traefik"              # gestito da Flux
      "--disable=metrics-server"       # Beszel copre monitoring
      "--write-kubeconfig-mode=0644"
    ];

    # Override del ConfigMap bundled: delega a Technitium per lab.paroparo.it.
    # Il nome "coredns" è richiesto da k3s (sovrascrive il ConfigMap built-in).
    # Kustomization "dyson": senza questo Flux clona il repo ma non sa cosa applicare.
    manifests."flux-cluster-kustomization" = {
      content = {
        apiVersion = "kustomize.toolkit.fluxcd.io/v1";
        kind = "Kustomization";
        metadata = {
          name = "dyson";
          namespace = "flux-system";
        };
        spec = {
          interval = "10m";
          path = "./k8s/clusters/dyson";
          prune = true;
          sourceRef = {
            kind = "GitRepository";
            name = "flux-system";
          };
        };
      };
    };
    # Al primo boot fallirà con "no CRD for GitRepository" (Flux non ancora installato);
    # k3s riprova automaticamente dopo che flux-helmchart ha installato le CRD.
    manifests."flux-git-repository" = {
      content = {
        apiVersion = "source.toolkit.fluxcd.io/v1";
        kind = "GitRepository";
        metadata = {
          name = "flux-system";
          namespace = "flux-system";
        };
        spec = {
          interval = "1m";
          url = "ssh://git@github.com/iltruma/astra";
          ref.branch = "main";
          secretRef.name = "flux-system";  # Secret SSH con identity/identity.pub/known_hosts
        };
      };
    };
    # HelmChart: il controller k3s built-in installa flux2; dopo l'install le CRD Flux
    # sono attive e i manifest flux-git-repository e flux-cluster-kustomization vengono applicati.
    manifests."flux-helmchart" = {
      content = {
        apiVersion = "helm.cattle.io/v1";
        kind = "HelmChart";
        metadata = { name = "flux2"; namespace = "kube-system"; };
        spec = {
          targetNamespace = "flux-system";
          createNamespace = true;
          chart = "oci://ghcr.io/fluxcd-community/charts/flux2";
          version = "2.19.0";
        };
      };
    };
    # Namespace esplicito: k3s non crea namespace implicitamente dai manifest.
    # Nome "flux-namespace" < "flux-secret-*" → ordine lessicale garantisce che il
    # namespace esista prima dei Secret.
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

  networking.firewall.allowedTCPPorts = [ 10250 ]; # kubelet API (richiesto da k3s metrics)

  environment.systemPackages = with pkgs; [ k3s fluxcd];
}
