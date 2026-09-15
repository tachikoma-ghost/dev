{
  description = "The dev environment as a microVM: a docker host for the work runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }:
    let system = "x86_64-linux";
    in {
      nixosConfigurations.unit = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ microvm.nixosModules.microvm ./microvm/unit.nix ];
      };

      # nix run .#unit   -- boots it in the foreground.
      # One attribute set: two `packages.${system}.<name> =` bindings are a
      # duplicate dynamic attribute, which nix rejects at parse time.
      packages.${system} = rec {
        unit = self.nixosConfigurations.unit.config.microvm.declaredRunner;
        default = unit;
      };
    };
}
