# Host-side tools for bin/devvm. The guest is Debian (the image the Dockerfile
# builds); this is only what runs outside it.
#
#   nix-shell vm-shell.nix --run 'bin/devvm unit start'
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    cloud-hypervisor # the VMM, and ch-remote with it
    virtiofsd # serves /workspace into the guest
    passt # userspace networking, so no tap and no CAP_NET_ADMIN
    e2fsprogs # mke2fs -d builds the rootfs without root
  ];
}
