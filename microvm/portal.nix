# The port manager: it publishes a signalshell app per activated TCP port, so
# a dev server in the guest is reachable without forwarding anything.
#
# Pinned release rather than a build from source, for the same reason as
# signalshell.nix: the guest is a docker host with no checkout and no Go.
{ lib, pkgs, ... }:

let
  version = "5";

  portal = pkgs.stdenvNoCC.mkDerivation {
    pname = "portal";
    inherit version;

    # CGO_ENABLED=0, so the release binary is static.
    src = pkgs.fetchurl {
      url = "https://signalshell.com/releases/portal/${version}/portal-linux-amd64";
      hash = "sha256-cvdcLHLMRcCtkL0fhWuhpVeQfAM0MyUMmzProUJvJYc=";
    };

    dontUnpack = true;
    installPhase = "install -Dm755 $src $out/bin/portal";

    meta.mainProgram = "portal";
  };
in
{
  environment.systemPackages = [ portal ];

  systemd.services.portal = {
    description = "portal port manager";
    wantedBy = [ "multi-user.target" ];

    # It registers over signalshell's app.sock and reconnects with backoff if
    # that socket is not there yet, so this orders the normal case without
    # making portal depend on signalshell being up.
    after = [ "signalshell.service" ];

    serviceConfig = {
      ExecStart = lib.getExe portal;
      User = "node";
      Restart = "always";
      RestartSec = 5;

      # Same home as signalshell: portal finds app.sock under that state dir,
      # and records which ports are activated next to it. Both must land on
      # the persistent volume, or every reboot forgets the activations.
      Environment = [ "HOME=/home/node" ];
      RequiresMountsFor = "/home/node";
    };
  };
}
