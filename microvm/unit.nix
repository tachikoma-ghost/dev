# A docker host, not a dev environment. The tooling lives in a project's own
# containers; this guest exists to run their daemon and to be reached over
# signalshell. See README.md for why a VM at all.
{ config, lib, pkgs, ... }:

let
  # The only share left is the read-only Nix store. 9p by default so a
  # foreground `nix run` needs no root; virtiofs once the VM is host-managed and
  # systemd starts virtiofsd for it. See microvm/host.nix.
  envProto = builtins.getEnv "DEV_SHARE_PROTO";
  shareProto = if envProto != "" then envProto else "9p";
  sshKey = ../setup/user/key.pub;
in
{
  imports = [ ./signalshell.nix ./portal.nix ./playwright.nix ];

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
      # It is read-only and mostly cached, so keeping it on 9p is cheap.
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = shareProto;
      }
    ];

    # Docker's layers, the home directory and the working tree all go on real
    # block devices, never a share.
    volumes = [
      {
        image = "docker.img";
        mountPoint = "/var/lib/docker";
        size = 20480;
      }
      # The root filesystem is tmpfs, so without this the ssh key for the forge,
      # tea's credentials and signalshell's host key would all have to be
      # recreated after every boot.
      {
        image = "home.img";
        mountPoint = "/home/node";
        size = 2048;
      }
      # The working tree. It was a 9p share of the host's directory until
      # 2026-09-19, when that share turned out to be the VM's entire CPU cost:
      # serving it spent ~44 CPU-hours in qemu's 9p server over a day (578M
      # virtio-9p requests, against ~9k for the virtio-blk docker.img), and 9p
      # carries no inotify, so a file-watching dev server had to poll it. On a
      # disk it is native block I/O and inotify works. The tree is no longer
      # visible to the host; clone your project into /workspace in the guest.
      {
        image = "workspace.img";
        mountPoint = "/workspace";
        size = 20480;
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

  # The dev tooling drives the daemon from here: a TypeScript CLI (bun), git
  # over ssh (git, openssh), and the forge's CLI (tea). Verified by building and
  # serving a compose stack on this daemon.
  environment.systemPackages = with pkgs; [ bun git openssh tea curl ];

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

  # /home/node is a freshly created ext4 volume, so it starts out owned by root.
  # Parent first: a rule for a deep path creates the directories above it owned
  # by root, and systemd-tmpfiles then refuses to descend through them ("unsafe
  # path transition"), which left ~/.local root-owned and signalshell unable to
  # create its state directory. Z repairs ownership that a previous boot got
  # wrong -- the home disk outlives the mistake, so creating it correctly is
  # not enough on its own. A mode of "-" leaves file modes alone.
  systemd.tmpfiles.rules = [
    "d /home/node 0700 node users -"
    "d /home/node/.local 0755 node users -"
    "Z /home/node/.local - node users -"
    # The workspace volume mounts root-owned; hand it to node so the checkout
    # (and the containers, which run as 1000:100) can write it. This runs after
    # local-fs.target, so it is the mounted ext4 root, not the tmpfs under it.
    "d /workspace 0755 node users -"
  ];

  networking.hostName = "unit-vm";
  system.stateVersion = "25.05";
}
