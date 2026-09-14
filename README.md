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

## Why DinD needs CAP_SYS_PTRACE

On a host running `kernel.yama.ptrace_scope=1`, rootless DinD fails at
`newuidmap: write to uid_map failed: Operation not permitted`.

Writing another process's `uid_map` requires ptrace access to it, not merely
`CAP_SETUID`. Yama at scope 1 grants that only along the ancestor line, and
`newuidmap` is a *sibling* of the process it maps, not an ancestor. A
non-ancestor needs `CAP_SYS_PTRACE`, which is absent from Docker's default
capability set -- so uid 0 in the container does not have it either, capabilities
being bounded by that set.

`cap_add: SYS_PTRACE` is therefore required alongside `security_opt`. It lets
processes in the container ptrace each other and confers nothing on the host.
Setting `kernel.yama.ptrace_scope=0` would also work and is a worse trade: it
weakens ptrace restrictions for the whole machine.

Hosts with `ptrace_scope=0` need neither, which is why this does not reproduce
everywhere.

**File ownership.** The rootless daemon maps container uid 0 to `node` and everything above it into the subuid range, so a container running as uid 1000 writes files that arrive as 100999 outside.
Run containers as root to keep bind-mounted files owned by `node`.
For Sail that means `sail artisan sail:publish`, then changing `user=sail` to `user=root` in `supervisord.conf`.
Setting `WWWUSER=0` does not work, because the entrypoint's `usermod` refuses a duplicate uid.

## License

MIT License.
See [LICENSE.md](LICENSE.md) for details.

