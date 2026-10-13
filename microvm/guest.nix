# The generic microVM guest: a docker host, not a dev environment. The
# tooling lives in a project's own containers; the guest exists to run their
# daemon (imported per instance) and to be reached over signalshell.
#
# Every VM the flake declares instantiates this module; adding an instance is
# one entry in flake.nix's `vms` list, no new file. Values that must be unique
# per VM and deterministic across rebuilds -- hostName, MAC, ssh forward port --
# are either passed explicitly or derived from the VM *name* by hash, so a
# rebuild can never accidentally shadow another VM's identity.
# Instantiation shape (see flake.nix): the file is a two-argument function —
#   guest = import ./microvm/guest.nix;
#   <module> = guest "eval" { hostName = ...; imports = [...]; };
# The name comes first as a plain argument; the entry fields are the second
# argument, each with a default. Applying both produces a plain module.
# Module arguments (lib, pkgs) are applied last, by the module system.
name:
{
  # The VM's identity under the flake and on the host (microvm.vms.<name>,
  # /var/lib/microvms/<name>). Also seeds the derived values below:
  # hostName, the interface id and the MAC.
  # Guest hostname.
  hostName ? "vm-" + name,
  # Locally administered MAC. Derived deterministically from the name when
  # omitted: prefix 02:00:00 (unregistered, safe for qemu user networking)
  # plus the first three bytes of a sha256 of the name.
  mac ? null,
  # Host-side ssh forward for rescue access; none when null.
  sshHostPort ? null,
  vcpu ? 4,
  mem ? 8192,
  dockerSize ? 20480,
  homeSize ? 2048,
  workspaceSize ? 20480,
  # Extra modules, e.g. ./microvm/signalshell.nix; signalshell stays the rule
  # (access), portal/playwright are per-instance choices.
  imports ? [],
  packages ? defaultPackages,
  # Disk image location. null (= unset, no DEVVM_VOLUMES_DIR env): the
  # microvm module's own per-VM layout, where unit's disks already live --
  # pinned in unit's entry. A path (or the env when the field is unset):
  # one central folder per usage, e.g. bin/devvm exports
  # $HOME/projects/devvm/volumes, giving "volumes/eval/docker.img".
  volumesDir ? builtins.getEnv "DEVVM_VOLUMES_DIR",
  # User config files copied into the guest's home once, at first boot --
  # what `dev init` does at image build and setup/agent.sh does per tool.
  # Map of target-in-/home/node to source path in this repo, e.g.
  # { ".gitconfig" = ../setup/user/gitconfig; }. Sources go into the guest
  # as store paths, so a VM rebuild re-copies from the new store path only
  # if the one-time run has not happened yet (see the marker below).
  userFiles ? {},
  # Extra first-boot provisioning lines (the Dockerfile's RUN lines), same
  # one-time semantics as userFiles. Instance scripts run as root; node has
  # passwordless sudo (wheel), so lines can su node where needed.
  setup ? [],
  stateVersion ? "25.05",
}:
{ lib, pkgs, ... }:

let
  # The only share left is the read-only Nix store. 9p by default so a
  # foreground `nix run` needs no root; virtiofs once the VM is host-managed and
  # systemd starts virtiofsd for it. See microvm/host.nix.
  envProto = builtins.getEnv "DEV_SHARE_PROTO";
  shareProto = if envProto != "" then envProto else "9p";
  sshKey = ../setup/user/key.pub;

  # Default tooling (as unit.nix shipped it): a TypeScript CLI driver (bun),
  # git over ssh, the forge CLI (tea). Instances override `packages` freely.
  defaultPackages = pkgs: with pkgs; [ bun git openssh tea curl ];
in

{
  imports = imports;

  microvm = {
    # qemu first, deliberately: its user-mode networking and port forwarding are
    # the best-supported combination, so the first boot changes one thing rather
    # than three. cloud-hypervisor is a one-word change once networking is
    # proven -- boot time is irrelevant for one long-lived VM.
    hypervisor = "qemu";

    inherit vcpu mem;

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
    # block devices, never a share. Image names are bare per VM state dir
    # (volumesDir = null) or absolute under one central folder per usage.
    volumes = let
      img = f: if volumesDir == null || volumesDir == ""
        then f
        else volumesDir + "/" + name + "/" + f;
    in [
      {
        image = img "docker.img";
        mountPoint = "/var/lib/docker";
        size = dockerSize;
      }
      # The root filesystem is tmpfs, so without this the ssh key for the forge,
      # tea's credentials and signalshell's host key would all have to be
      # recreated after every boot.
      {
        image = img "home.img";
        mountPoint = "/home/node";
        size = homeSize;
      }
      # The working tree. It was a 9p share of the host's directory until
      # 2026-09-19, when that share turned out to be the VM's entire CPU cost:
      # serving it spent ~44 CPU-hours in qemu's 9p server over a day (578M
      # virtio-9p requests, against ~9k for the virtio-blk docker.img), and 9p
      # carries no inotify, so a file-watching dev server had to poll it. On a
      # disk it is native block I/O and inotify works. The tree is no longer
      # visible to the host; clone your project into /workspace in the guest.
      {
        image = img "workspace.img";
        mountPoint = "/workspace";
        size = workspaceSize;
      }
    ];

    interfaces = [{
      type = "user";
      id = "vm-" + name;
      mac = if mac != null
        then mac
        else "02:00:00:"
          + builtins.substring 0 2 (builtins.hashString "sha256" name) + ":"
          + builtins.substring 2 2 (builtins.hashString "sha256" name) + ":"
          + builtins.substring 4 2 (builtins.hashString "sha256" name);
    }];

    forwardPorts = lib.optionals (sshHostPort != null) [{
      from = "host";
      host.port = sshHostPort;
      guest.port = 22;
    }];
  };

  virtualisation.docker.enable = true;

  # Verified by building and serving a compose stack on this daemon.
  environment.systemPackages = packages pkgs;

  # A project that loads its environment from an .envrc gets it in an
  # interactive shell, as on a workstation (`direnv allow` once per checkout).
  # The hook does not fire in a non-interactive shell; a script there runs
  # `direnv exec <dir> <command>`.
  programs.direnv.enable = true;

  # Prebuilt foreign binaries. A project's tooling can arrive as single-file
  # compiled executables -- bun's compiler emits one -- and those link against
  # a generic glibc with libstdc++, which this guest cannot run: the store
  # layout has no /lib64 loader path and no system-wide library dir. nix-ld
  # provides the conventional interpreter path, forwarding to the store loader
  # with NIX_LD_LIBRARY_PATH built from this list, so such a binary runs
  # as-is instead of needing a container or a patchelf pass.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc # libstdc++ and the gcc runtime
      libgcc # libgcc_s
    ];
  };

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

  networking.hostName = hostName;
  system.stateVersion = stateVersion;

  # First-boot provisioning: copy userFiles into /home/node, then run the
  # instance's setup lines. A oneshot with a marker on the persistent home
  # disk, so it behaves like a docker image build: every boot after the first
  # skips it, and hand-edits a user made inside the guest are never clobbered.
  systemd.services.devvm-setup = lib.mkIf (userFiles != {} || setup != []) {
    description = "devvm per-instance provisioning (config files + setup)";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
    # The home disk persists across reboot and rebuild; the marker lives
    # where almost everything persistent on this guest lives.
    unitConfig.ConditionPathExists = "!/home/node/.local/state/devvm-setup.done";
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (target: src:
        # 600 by default: files copied here are typically credentials or
        # personal config; the broader-readable ones can chmod up inside.
        "install -D -m 600 -o node -g users '${src}' '/home/node/${target}'"
      ) userFiles)}
      ${lib.concatStringsSep "\n" setup}
      mkdir -p /home/node/.local/state
      touch /home/node/.local/state/devvm-setup.done
    '';
  };
}
