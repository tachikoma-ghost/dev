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

Some tools bring their own containers: Laravel Sail, Testcontainers, a project's own `docker compose`.
Those need a real Docker daemon rather than a socket pointed at the host's, so the container ships an optional rootless one.

It is rootless rather than the usual privileged Docker-in-Docker.
A privileged daemon can mount host block devices and load kernel modules, so anything able to reach it has root on the host by design.
The rootless daemon runs as `node` inside a user namespace: container root maps to an unprivileged uid, block devices cannot be mounted at all, and read-only mounts stay read-only.

**To enable**, uncomment three lines, each commented and cross-referenced:

1. `docker-compose.yml`: the `security_opt` block, without which the daemon cannot create its user namespace and exits immediately
2. `Dockerfile`: the `RUN /setup/dind.sh` line
3. `Dockerfile`: the `RUN /setup/section3.sh` line, which installs the supervisor the entrypoint then runs. `setup/dind.sh` declares dockerd as a service in `~/.config/section3/conf.d/`, and section3 reads it on start. Without section3, start it yourself: `XDG_RUNTIME_DIR=/run/user/$(id -u) dockerd-rootless.sh`

Then `dev build` and `dev start`.

**To check it worked:**

```
docker info | grep -i 'storage driver'   # overlay2, never vfs
docker run --rm hello-world
```

**What it costs.** A wider kernel attack surface: user namespaces plus `mount` reach code paths with a history of local privilege escalation bugs, CVE-2022-0185 and CVE-2023-0386 among them.
It grants no new authority over the host.
The block is needed because Docker's default seccomp profile blocks `clone(CLONE_NEWUSER)` without `CAP_SYS_ADMIN`.
A narrower custom profile instead of `unconfined` is possible, but it still has to allow `mount`, `unshare`, `setns`, `pivot_root` and the new mount API, so it buys less than it looks like it should.
Sub-containers can be handed anything the dev container can see, so keep the paths you mount into them narrow.

## Booting as a NixOS microVM (flake.nix)

On a NixOS host this is the shorter path. `microvm.nix` supplies the guest
kernel, the initrd, the virtiofs shares and the networking, all of which
`bin/devvm` does by hand -- and both bugs found in that script so far were in
exactly those parts.

    nix run .#unit          # boot it in the foreground
    signalshell invite tachikoma    # from inside, for remote access
    ssh -p 2222 node@127.0.0.1      # only if setup/user/key.pub exists

`signalshell serve` runs as a systemd unit from boot (`microvm/signalshell.nix`,
a pinned release binary -- the guest has no checkout and no toolchain). It dials
out to the relay, so the forwarded port is a convenience, not the way in.
section3 is not used here: it exists because a container has no init, and this
guest has systemd.

Its host key lives on a small persistent volume at `/var/lib/signalshell`. That
is deliberate: in the container the key lives in the image, so every rebuild
mints a new identity and silently invalidates the connection string saved on the
other side.

To start it at boot instead of in a foreground shell, the host takes the
`microvm.nix` host module and declares the guest:

    microvm.vms.unit.flake = "/path/to/projects/unit/dev";

The shared host directory is **not** in the repo -- this one is public. It comes
from the environment, and the run has to be impure to read it:

    out=$(DEV_PROJECT_DIR="$PWD/.." nix build --impure --no-link --print-out-paths .#unit)
    $out/bin/virtiofsd-run &     # the shares are virtiofs; qemu needs its sockets
    $out/bin/microvm-run

`nix run .#unit` alone is not enough: it starts the VM and not the virtiofsd
daemons behind `microvm.shares`, so qemu fails with `Failed to connect to
unit-vm-virtiofs-ro-store.sock`. Only the systemd host module
(`microvm.vms.<name>`) starts both in the right order. Switching the shares to
`proto = "9p"` would also work -- qemu implements 9p itself, no daemon -- at a
cost in filesystem performance.

A gitignored file will not work for this: flakes only see git-tracked files, so
`microvm/local.nix` is invisible to evaluation unless you track it in a private
fork, which is the other supported way to set `projectDir`.

That, `/dev/kvm` access, and docker on the host for `bin/devvm image` are the
only host-side requirements; nothing here needs root or a host daemon change.

The guest is NixOS and is **not** a dev environment: it runs docker and sshd,
and the tooling lives in the work runtime's containers, which bring their own
image. That is what makes the guest OS a free choice.

`microvm/unit.nix` shares `~/projects/unit` at `/workspace` over virtiofs and
gives docker its own block device, because image layers on a virtiofs share are
both slow and a way to leak guest uids into a host directory.

It starts on qemu rather than cloud-hypervisor on purpose: user-mode networking
with port forwarding is best supported there, so the first boot changes one
thing instead of three. Switching is one word once networking is proven, and
boot time does not matter for a VM that runs all day.

**Untested.** Written without a NixOS host to evaluate it on. Expect
`microvm.nix` option names to need checking against the version you get.

## Booting the image as a VM (bin/devvm)

`bin/devvm` boots the same image under cloud-hypervisor instead of running it as
a container. Inside, root is real root and docker is the ordinary rootful
daemon; the hypervisor is what keeps that away from the host, so it concedes
nothing a privileged container or a bound host socket would have conceded.

    devvm <project> deps     # cloud-hypervisor (pinned + checksummed), virtiofsd, passt, /dev/kvm
    devvm <project> image    # docker build -> docker export -> ext4 rootfs
    devvm <project> kernel   # extract a PVH vmlinux from the image's kernel
    devvm <project> start
    devvm <project> ssh

**Host permissions: membership of the `kvm` group, and nothing else.** passt
does the networking in userspace, so no tap device and no CAP_NET_ADMIN;
`mke2fs -d` builds the rootfs without root; virtiofsd runs unprivileged because
it only ever shares your own files.

**`/workspace` is virtio-fs**, not a bind mount, and virtio-fs is slower than a
bind mount on metadata-heavy work -- `git status`, `bun install`, anything
walking `node_modules`. Keep docker's storage on the VM's own disk, never on the
share.

**The kernel has to be a PVH entry point.** cloud-hypervisor does not boot the
compressed bzImage distros ship, so `devvm kernel` extracts a vmlinux and checks
for the Xen PVH note before you find out the hard way at boot. If your kernel
lacks it, build one per cloud-hypervisor's `docs/custom_kernel.md`.

**Untested.** Written against the documented interfaces of cloud-hypervisor
v53.0, virtiofsd and passt, but never booted -- there was no KVM on the machine
it was written on. Expect the first run to need corrections.

## A daemon in a VM, instead

Rootless DinD does not work on every host. On a 6.18.40 kernel with rootlesskit
3.1.0 it fails at `newuidmap: write to uid_map failed: Operation not permitted`,
and that is not a configuration problem: real root can write the same map for
any namespace created with `unshare`, but not for rootlesskit's own child.
Capabilities, seccomp, AppArmor, `/etc/subuid` and the setuid helpers were all
eliminated by measurement.

The alternative that keeps the isolation intent is a VM on the host running a
normal rootful daemon, with the container holding only the client. Guest root is
not host root, so it concedes nothing the socket bind would have.

**To enable**, uncomment `RUN /setup/docker-cli.sh` in the `Dockerfile` and set
`DOCKER_HOST` in `docker-compose.yml`. The `security_opt` block stays commented:
without a local daemon nothing here creates a user namespace.

The daemon's TCP port grants root *in the VM* to whoever reaches it, so bind it
to an interface only the host and its containers can see.

**File ownership.** The rootless daemon maps container uid 0 to `node` and everything above it into the subuid range, so a container running as uid 1000 writes files that arrive as 100999 outside.
Run containers as root to keep bind-mounted files owned by `node`.
For Sail that means `sail artisan sail:publish`, then changing `user=sail` to `user=root` in `supervisord.conf`.
Setting `WWWUSER=0` does not work, because the entrypoint's `usermod` refuses a duplicate uid.

## License

MIT License.
See [LICENSE.md](LICENSE.md) for details.

