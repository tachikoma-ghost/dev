# A docker host, not a dev environment. The tooling lives in the work runtime's
# own containers; this guest exists to run their daemon and to be reached over
# signalshell. See README.md for why a VM at all.
{ config, lib, pkgs, ... }:

let
  # The host directory shared into the guest. Deliberately not in the repo:
  # this one is public, and the path names somebody's home.
  #
  # It comes from the environment, because a flake only sees git-tracked files:
  # a gitignored microvm/local.nix is invisible to evaluation, which is what
  # made the first boot attempt fail.
  #
  #     DEV_PROJECT_DIR="$PWD/.." nix run --impure .#unit
  #
  # microvm/local.nix still works if you track it in a private fork.
  local = if builtins.pathExists ./local.nix then import ./local.nix else { };
  envDir = builtins.getEnv "DEV_PROJECT_DIR";

  # 9p by default so a foreground `nix run` needs no root; virtiofs once the VM
  # is host-managed and systemd starts virtiofsd for it. See microvm/host.nix.
  envProto = builtins.getEnv "DEV_SHARE_PROTO";
  shareProto = if envProto != "" then envProto else "9p";
  projectDir = local.projectDir or (
    if envDir != "" then envDir
    else throw ("microvm: set DEV_PROJECT_DIR and run with --impure, e.g. "
      + "DEV_PROJECT_DIR=\"$PWD/..\" nix run --impure .#unit -- see README.md"));
  sshKey = ../setup/user/key.pub;
in
{
  imports = [ ./signalshell.nix ];

  microvm = {
    # qemu first, deliberately: its user-mode networking and port forwarding are
    # the best-supported combination, so the first boot changes one thing rather
    # than three. cloud-hypervisor is a one-word change once networking is
    # proven -- boot time is irrelevant for one long-lived VM.
    hypervisor = "qemu";

    vcpu = 4;
    mem = 8192;

    # Protocol from DEV_SHARE_PROTO, 9p by default: virtiofs needs a virtiofsd
    # per share, and the command-line runner supervises them expecting to be
    # root, while qemu implements 9p itself.
    shares = [
      # A NixOS guest runs from the host's store; without this it has no system.
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = shareProto;
      }
      {
        tag = "workspace";
        source = projectDir;
        mountPoint = "/workspace";
        proto = shareProto;
      }
    ];

    # Docker's layers go on a real block device. On the virtiofs share they
    # would be slow and would leak the guest's uids into the host directory.
    volumes = [
      {
        image = "docker.img";
        mountPoint = "/var/lib/docker";
        size = 20480;
      }
      # signalshell's host key lives here. Without a volume it would be minted
      # afresh on every rebuild, invalidating the saved connection string.
      {
        image = "state.img";
        mountPoint = "/var/lib/signalshell";
        size = 64;
      }
    ];

    interfaces = [{
      type = "user";
      id = "vm-unit";
      mac = "02:00:00:01:01:01";
    }];

    forwardPorts = [{
      from = "host";
      host.port = 2222;
      guest.port = 22;
    }];
  };

  virtualisation.docker.enable = true;

  users.users.node = {
    isNormalUser = true;
    extraGroups = [ "docker" "wheel" ];
    # Same key the container image uses, so one file stays the source of truth.
    # Optional: there is no key in the repo, and a missing path would be an
    # evaluation error rather than a guest you simply reach over signalshell.
    openssh.authorizedKeys.keyFiles = lib.optionals (builtins.pathExists sshKey) [ sshKey ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # The console is reachable only from the terminal that launched the VM, and
  # node has no password (the ssh key is optional and absent by default), so
  # without this a foreground boot ends at a login prompt nobody can answer.
  services.getty.autologinUser = "node";

  networking.hostName = "unit-vm";
  system.stateVersion = "25.05";
}
