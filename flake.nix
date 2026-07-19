{
  description = "Astra — NixOS fleet (Dell Optiplex 3050 + Raspberry Pi 4)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Install:
    #   nix run github:nix-community/nixos-anywhere -- \
    #     --flake .#nebula --build-on local \
    #     --target-host root@192.168.178.2 \
    #     --extra-files <dir-con-chiave-age>
    # Vedi docs/00-nixos-installation.md §3 per il bootstrap sops
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    impermanence.url = "github:nix-community/impermanence";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, sops-nix, disko, nixos-anywhere, impermanence, nixos-hardware, ... }: {
    nixosConfigurations.nebula = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
      };
      modules = [
        ./hosts/nebula
        sops-nix.nixosModules.sops
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
      ];
    };

    # nixos-rebuild switch --flake .#taiga --target-host pi@192.168.178.43 --build-host localhost
    nixosConfigurations.taiga = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./hosts/taiga
        nixos-hardware.nixosModules.raspberry-pi-4
        sops-nix.nixosModules.sops
      ];
    };

    # nix build .#nixosConfigurations.installer.config.system.build.isoImage
    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/installer ];
    };
  };
}
