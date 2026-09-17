# Remote access to the guest, and the reason no port needs forwarding: the
# daemon dials out to the relay, so qemu's user-mode networking is enough.
#
# The binary is a pinned release rather than a build from source: the guest is
# a docker host, not a dev environment, so it has no checkout and no toolchain.
{ lib, pkgs, ... }:

let
  version = "393";

  signalshell = pkgs.stdenvNoCC.mkDerivation {
    pname = "signalshell";
    inherit version;

    # CGO_ENABLED=0, so the release binary is static: no patchelf, no libc.
    src = pkgs.fetchurl {
      url = "https://signalshell.com/releases/${version}/signalshell-linux-amd64";
      hash = "sha256-5mHYWQZwHhj7h58TXNoxC6HNk9zF7ykvbNSPT1WB59M=";
    };

    dontUnpack = true;
    installPhase = "install -Dm755 $src $out/bin/signalshell";

    meta.mainProgram = "signalshell";
  };
in
{
  # `signalshell serve` refuses to start without tmux: sessions are tmux panes.
  environment.systemPackages = [ signalshell pkgs.tmux pkgs.rsync ];

  systemd.services.signalshell = {
    description = "signalshell remote access";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # systemd's default PATH has neither bash nor tmux, so `serve` died on
    # every start with `spawn PTY: exec: "bash": executable file not found`.
    # This is also the PATH every pane inherits, so everything a session is
    # expected to use is named here. A bare "/run/current-system/sw/bin" string
    # does not work: the option takes packages, and a session opened without
    # docker, git, bun or tea on PATH.
    path = with pkgs; [
      bashInteractive
      tmux
      docker
      git
      openssh
      bun
      tea
      curl
      rsync
    ];

    serviceConfig = {
      ExecStart = "${lib.getExe signalshell} serve";
      User = "node";
      Restart = "always";
      RestartSec = 5;

      # The host key IS the guest's identity: in a container it lives in the
      # image, so every rebuild mints a new one and silently invalidates the
      # connection string saved on the other side. Here it lands in node's home,
      # which is a persistent volume -- and, being the default location, it is
      # also where `signalshell invite` in a login shell looks for the control
      # socket. Pointing the service somewhere else made the CLI report the
      # server as not running while it was up.
      Environment = [ "HOME=/home/node" ];
      # The identity is on that volume, so do not start before it is mounted.
      RequiresMountsFor = "/home/node";
    };
  };
}
