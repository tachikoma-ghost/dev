# Dev Container

Safe, isolated development environments for trying out projects without risking your machine.

**Key features:**
- Runs each project in an isolated Docker container
- CLI-based development: nvim, AI agents, etc.
- Transparent port forwarding: access apps in your browser as if they were running on the host
- Scripts are easy to audit: less than 300 lines of bash running on the host
- Minimal dependencies: docker, docker-compose, git, bash, ssh

As a side effect, you get clean, reproducible, and easy-to-reset development environments.

No more `npm install` on your host, no AI agents reading your files.
Safely experiment with any project.

## How it works

Simple, transparent scripts you can easily audit:
- Main script `bin/dev`: ~200 lines of bash, mostly if/else and case statements, linear, no recursion
- Port forwarding `bin/ports`: ~50 lines of bash, starting a ssh tunnel with `ssh -L ...`
- Docker-compose file: ~30 lines of yaml, defining services and volumes
- Dockerfile: ~20 lines, defining the base image and which tools to install by default
- Setup scripts in `setup/`: ~5-30 lines of bash each

You are supposed to modify the Dockerfile and setup scripts to fit your needs.
The docker-compose file can also be used to include additional services or enable permanent port forwarding.

## Install

Requires docker, docker-compose and some basic tools like git, bash and ssh.

The command `bin/dev` should be somewhere in your PATH.

```
mkdir -p ~/bin
wget https://raw.githubusercontent.com/f0i/dev/refs/heads/main/bin/dev -O ~/bin/dev
echo "export PATH=\"$PATH:$HOME/bin\" >> ~/.bashrc"
```

All other files will be added per project as needed:

1. Assuming a project called `arena` in `~/projects/arena`
2. Clone this repo into the project root `dev arena init`
3. During init, you'll be prompted to:
   - Copy your SSH public key and `.gitconfig` (choose **yes** to copy to `setup/user/`, or **no** to configure manually later)
   - Clone a nvim configuration (automatically detects your `~/.config/nvim` git remote, or uses default)
4. Modify the `Dockerfile` to include the services and tools you need
5. Build the docker container using the command `dev build`
6. Start the docker container with `dev start`
7. Connect to the container with `dev` and start development
8. Enable port forwarding to the host `dev ports 3000 8080:80`,
   in this case port 3000 and 8080 of the host will be forwarded to port 3000 and 80 of the container

## Updating

Pull first, then apply. `dev upgrade` runs `git pull` here and in `nvim/`, and stops there. It does not build or restart anything.
What you need after that depends on what changed.

| Changed | Command |
|---|---|
| `Dockerfile`, `setup/*.sh` | `dev build`, then `dev start` |
| `docker-compose.yml` | `dev start` |
| `bin/dev`, `bin/ports` | nothing, they run on the host |

`dev start` is `docker-compose up -d`, not `docker-compose start`.
It recreates the container when the compose config or the image changed, and leaves it alone otherwise, so it is safe to run at any time.
It never builds: skip `dev build` and it will happily keep the old image.

Recreating replaces the running container, and anything live inside it goes too: shells, tmux sessions, background processes. The `/workspace` bind survives, the home directory does not.

**Getting newer packages.** An unchanged `Dockerfile` means every layer is a cache hit, so a plain `dev build` is fast and changes nothing. That also means it does not pick up new versions: a `RUN` layer is cached on the command string, not on what the command would download, so `curl … | bash` installers stay at whatever version they first built. Two separate needs:

```
dev build --no-cache      # re-run every step: new versions of curl-installed tools
dev build --pull          # newer base image: distribution package updates
```

Arguments are passed through to `docker-compose`, so the two combine.

## AI agents

`setup/agent.sh` installs Claude Code, opencode and the Gemini CLI.
Comment out the `RUN /setup/agent.sh` line in the `Dockerfile` to leave them out, or edit the script to change the set.

`setup/user/claude/settings.json` is copied to `~/.claude/` and sets three defaults for Claude Code:

- no attribution on commits or pull requests, and no session link
- Remote Control off at startup, so a session is reachable from outside only after you run `/remote-control`
- approval required before Claude messages one of your sessions on another machine, which is the case that travels through Anthropic's servers

Edit that file to change them.
Claude Code writes its own settings there too, so a container keeps whatever you change inside it until it is rebuilt.

## Nvim Configuration

During `dev init`, the nvim configuration is cloned into `./dev/nvim` and mounted at `/home/node/.config/nvim` inside the container.

**Why not mount `~/.config/nvim` directly?**
- **Isolation**: Each project gets its own nvim config for reproducibility
- **No modifications**: Prevents the container from modifying your personal config files
- **Different needs**: Container setup might need different plugins/settings than your host

**Using a different nvim config:**
- During init, it auto-detects the git remote of your `~/.config/nvim` if it exists
- Or you can manually clone any nvim config repo to `./dev/nvim` before building
- Or skip the nvim setup during init and add it later

## Docker in Docker

Not possible in this container, and not for want of a flag. Two kernel rules
decide it, both measured on a 6.18.40 host in September 2026:

1. Writing a multi-range `uid_map` needs `CAP_SETUID` in the parent namespace
   *and* the writer's euid to equal the namespace's owner. `newuidmap` is
   setuid-root, so its euid is 0 while the namespace it must map is owned by an
   unprivileged uid, and it can never satisfy both. Granting the capability as a
   file capability instead (`chmod u-s` plus `setcap cap_setuid+ep`) fixes that
   half: NixOS wraps it that way, Debian ships it setuid.
2. A new procfs mount is refused unless the mounter already sees a fully visible
   `/proc`. Docker's masked and read-only paths make it not visible, and those
   mounts are locked, so nothing inside the container can undo them. Every
   nested runtime needs to mount `/proc`, runc, crun, podman and buildah alike,
   so this is not specific to Docker and swapping the runtime does not help.

Past the first rule the daemon starts, pulls images and initializes buildkit.
It fails at the second, when runc mounts `/proc` for the container.

The only lever is `--security-opt systempaths=unconfined`, which unmasks
`/proc` and makes host-global sysctls writable. `kernel.core_pattern` there is
executed by the host kernel as real root, so that flag is host root by another
name and this repository does not offer it. Use the microVM below instead.

## Booting as a NixOS microVM (flake.nix)

On a NixOS host this is the path that works, and it is the reason the section
above exists only to say why containers cannot do it. `microvm.nix` supplies the
guest kernel, the initrd, the shares and the networking. Inside, docker is the
ordinary rootful daemon: guest root is not host root, so the hypervisor concedes
nothing that a privileged container or a bound socket would have.

    nix run .#unit

The serial console autologins as `node`, since it is reachable only from the
terminal that started the VM. (The old `DEV_PROJECT_DIR="$PWD/.." nix run
--impure` form went with the workspace share -- see **The working tree** below.)

Verified on 2026-09-15: `docker run --rm hello-world`, a compose stack building
and serving, git over ssh and the forge CLI all work in the guest.

**Access.** `signalshell serve` runs as a systemd unit from boot
(`microvm/signalshell.nix`, a pinned release binary, since the guest has no
checkout and no toolchain). It dials out to a relay, so the forwarded ssh port
is a convenience rather than the way in, and `ssh -p 2222 node@127.0.0.1` works
only if `setup/user/key.pub` exists. section3 is not used here: it exists
because a container has no init, and this guest has systemd.

**Persistence.** `/home/node`, `/var/lib/docker` and `/workspace` are disks, the
root filesystem is tmpfs. Everything worth keeping, the signalshell identity in
`~/.local/state/signalshell`, ssh keys, forge credentials and image layers,
survives a reboot or a rebuild. Moving that state is what invalidates a saved
connection string, so leave it where it is.

**At boot, rather than in a terminal.** Import `microvm/host.nix` into the
host's `configuration.nix`, which declares `microvm.vms.unit`. systemd then
starts the guest and, before it, one `virtiofsd` per share.

**Shares.** Only `/nix/store` is shared now (read-only and mostly cached); the
working tree is a disk. 9p is the default, so a foreground boot needs nothing
but `kvm` group membership. virtiofs is faster but needs a `virtiofsd` per
share, and the command-line runner supervises them expecting to be root (`Can't
drop privilege as nonroot user`). Once the VM is host-managed, switch with
`DEV_SHARE_PROTO=virtiofs` -- an environment read, so it needs `--impure`.

**The working tree** is `workspace.img`, mounted at `/workspace`, and is *not*
visible to the host. Clone the product repository into `/workspace/product` from
the forge in the guest.

This is deliberate. As a 9p share of the host's directory it was the VM's entire
CPU cost: serving the tree spent ~44 CPU-hours in qemu's 9p server over a day
(578M virtio-9p requests, against ~9k for the virtio-blk `docker.img`), and 9p
carries no inotify, so Vite polled it every 400 ms. On ext4 the I/O is native
block traffic and inotify works, so polling can go. The cost is that the host no
longer sees the tree; edit in the guest, or move code through the forge.

## A daemon elsewhere (docker-cli.sh)

The container can also hold only the docker client and talk to a daemon that
lives somewhere else, which is what the microVM above provides. Uncomment `RUN
/setup/docker-cli.sh` in the `Dockerfile` and set `DOCKER_HOST` in
`docker-compose.yml`.

Whoever reaches that daemon has root in the VM, so bind it to an interface only
the host and its containers can see.

## License

MIT License.
See [LICENSE.md](LICENSE.md) for details.

