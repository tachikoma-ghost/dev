# Every VM the flake declares, one entry each. flake.nix imports this file;
# `devvm init <name>` scaffolds a new entry above the marker comment, which is
# why the list lives in its own file and not in the flake.
#
# Fields are those of microvm/guest.nix's second argument; everything left out
# has a working default there. `volumesDir = null` keeps the microvm module's
# own per-VM layout (what unit has always used); unset means the
# DEVVM_VOLUMES_DIR environment variable if set -- bin/devvm exports
# $HOME/projects/devvm/volumes for it.

[
  {
    name = "unit";
    hostName = "unit-vm";
    mac = "02:00:00:01:01:01"; # explicit: unit predates the derivation
    sshHostPort = 2222;
    volumesDir = null; # pinned: keep unit's existing disk locations
    imports = [
      ./signalshell.nix
      ./portal.nix
      ./playwright.nix
    ];
  }
  {
    name = "eval";
    # hostname defaults to vm-eval, MAC 02:00:00:<hash(name)>, no ssh
    # forward -- access via signalshell only; ssh-forwarded rescue
    # matters for unit because its host has consumers on 2222, while
    # here the eval runs throwaway containers that signalshell reaches.
    homeSize = 1024; # no forge credentials live on this guest
    imports = [ ./signalshell.nix ];
    packages = pkgs: with pkgs; [ docker git openssh curl rsync ];
  }

  # devvm init adds new entries above this comment
]
