{
  description = "The dev environment as microVMs: docker hosts for projects' containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";

      # The VM list lives in microvm/vms.nix so `devvm init` can scaffold a new
      # instance by editing one file for one purpose. See the header there.
      vms = import ./microvm/vms.nix;

      # The name is guest.nix's first argument; the rest of the entry fields
      # are its second. Applying both yields a plain module for nixosSystem.
      guest = import ./microvm/guest.nix;
      mkGuest = entry: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          (guest entry.name (removeAttrs entry [ "name" ]))
        ];
      };
    in {
      nixosConfigurations = builtins.listToAttrs
        (map (entry: { name = entry.name; value = mkGuest entry; }) vms);

      # nix run .#<name>  -- boots that VM in the foreground.
      # One attribute set literal in the old form hit nix's duplicate dynamic
      # attribute rejection already with two VMs; mapAttrs over the
      # configurations keeps every new VM's runner available for free.
      packages.${system} = builtins.mapAttrs
        (_: nixos: nixos.config.microvm.declaredRunner)
        self.nixosConfigurations
        // { default = self.nixosConfigurations.unit.config.microvm.declaredRunner; };
    };
}
