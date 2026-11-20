# Example: run the guest as a host service instead of in a foreground shell.
#
# Import this from the host's configuration.nix (or copy the two lines into
# it). systemd then starts the VM at boot.
#
#   imports = [ /path/to/projects/unit/dev/microvm/host.nix ];
{ ... }:

{
  # microvm.nixosModules.host comes from the same flake input the guest uses;
  # add the flake as an input of the host's configuration to get it.
  microvm.vms.unit = {
    # The flake that defines nixosConfigurations.unit -- this repository.
    flake = /home/you/projects/unit/dev;
    updateFlake = "/home/you/projects/unit/dev";
    restartIfChanged = true;
  };

  # Useful when the guest is a build host: let it start before anything that
  # expects a docker daemon on the other side of signalshell.
  systemd.services."microvm@unit".wantedBy = [ "multi-user.target" ];
}
