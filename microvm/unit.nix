# A docker host, not a dev environment. The tooling lives in the work runtime's
# own containers; this guest exists to run their daemon and to be reached over
# ssh. See README.md for why a VM at all.
{ config, lib, pkgs, ... }:

let
  # The host directory shared into the guest. Adjust to your own home.
  projectDir = "/home/martin/projects/unit";
in
{
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
    volumes = [{
      image = "docker.img";
      mountPoint = "/var/lib/docker";
      size = 20480;
    }];

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
    openssh.authorizedKeys.keyFiles = [ ../setup/user/key.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  networking.hostName = "unit-vm";
  system.stateVersion = "25.05";
}
