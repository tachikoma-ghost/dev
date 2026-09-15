# Example: run the guest as a host service instead of in a foreground shell.
#
# Import this from the host's configuration.nix (or copy the two lines into
# it). systemd then starts the VM at boot and, crucially, starts a virtiofsd
# per share before it -- the ordering the command-line runner leaves to you.
#
#   imports = [ /path/to/projects/unit/dev/microvm/host.nix ];
#
# With the VM host-managed, the shares should go back to virtiofs, which is
# markedly faster than 9p on metadata-heavy work:
#
#   DEV_SHARE_PROTO=virtiofs
#
# set in the environment where the flake is evaluated, or just edit the default
# in microvm/unit.nix.
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
