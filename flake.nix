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

      # nix run .#unit   -- boots it in the foreground
      packages.${system}.unit =
        self.nixosConfigurations.unit.config.microvm.declaredRunner;
      packages.${system}.default = self.packages.${system}.unit;
    };
}
