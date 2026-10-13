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

      # Every VM is one entry here. guest.nix (microvm/guest.nix) supplies the
      # body; an entry only names the instance and overrides what differs.
      # Values left out are derived: hostName, MAC and (future) ports come from
      # `name` deterministically, so a rebuild never shadows another VM.
      #
      # `imports` paths are relative to this flake.nix. What each entry needs:
      #  - ./microvm/signalshell.nix for signalshell access (the rule, not the
      #    exception -- a VM nobody can reach cannot be administered).
      #  - portal/playwright stay with the instance that actually uses them.
      #
      # Foreground boot:  nix run .#<name>     (see packages below)
      # Host-managed:     microvm.vms.<name> in host.nix, as before.
      vms = [
        {
          name = "unit";
          hostName = "unit-vm";
          mac = "02:00:00:01:01:01"; # explicit: unit predates the derivation
          sshHostPort = 2222;
          imports = [
            ./microvm/signalshell.nix
            ./microvm/portal.nix
            ./microvm/playwright.nix
          ];
        }
        {
          name = "eval";
          # eval-vm, MAC 02:00:00:<hash(name)>, no ssh forward -- rescue access
          # via signalshell; ssh matters for unit because the daemon ships
          # with it, here the eval runs in throwaway containers only.
          homeSize = 1024; # no forge credentials live on this guest
          imports = [ ./microvm/signalshell.nix ];
          packages = pkgs: with pkgs; [ docker git openssh curl rsync ];
        }
      ];

      mkGuest = entry: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          (import ./microvm/guest.nix ({
            inherit (entry) name;
          } // (removeAttrs entry [ "name" "size" ])))
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
