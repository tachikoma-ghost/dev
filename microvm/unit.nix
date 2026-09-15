# A docker host, not a dev environment. The tooling lives in the work runtime's
# own containers; this guest exists to run their daemon and to be reached over
# signalshell. See README.md for why a VM at all.
{ config, lib, pkgs, ... }:

let
  # The host directory shared into the guest. Deliberately not in the repo:
  # this one is public, and the path names somebody's home. Put it in
  # microvm/local.nix, which is gitignored:
  #
  #     { projectDir = "/home/you/projects/unit"; }
  local = if builtins.pathExists ./local.nix then import ./local.nix else { };
  projectDir = local.projectDir or (throw
    "microvm: set projectDir in microvm/local.nix -- see README.md");
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

    shares = [
      # A NixOS guest runs from the host's store; without this it has no system.
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
      {
        tag = "workspace";
        source = projectDir;
        mountPoint = "/workspace";
        proto = "virtiofs";
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

  networking.hostName = "unit-vm";
  system.stateVersion = "25.05";
}
