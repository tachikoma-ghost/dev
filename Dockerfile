FROM mcr.microsoft.com/devcontainers/typescript-node

# The build has no tty; without this debconf logs a Dialog/Readline/Teletype
# fallback chain. ARG, not ENV, so interactive apt in the container still asks.
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /home/node
COPY setup /setup

# Let DEBIAN_FRONTEND pass sudo's env_reset.
RUN echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/keep-frontend

USER node

# claude, section3 and signalshell install here. .bashrc adds it for interactive
# shells, which the entrypoint is not.
ENV PATH=/home/node/.local/bin:$PATH

RUN /setup/updates.sh
RUN USER=node /setup/sshd.sh
RUN /setup/tmux.sh
RUN /setup/terminfo.sh
RUN /setup/bash.sh
RUN /setup/nvim.sh
RUN /setup/agent.sh
RUN /setup/bun.sh
RUN /setup/unitscale.sh
#RUN /setup/icp.sh
#RUN /setup/rust.sh
RUN /setup/section3.sh
RUN /setup/signalshell.sh

# Rootless Docker-in-Docker. Needs the security_opt block in
# docker-compose.yml, and section3 above to start the daemon: dind.sh
# declares it as a service in ~/.config/section3/conf.d/. See README.md.
RUN /setup/dind.sh

ENTRYPOINT ["/setup/entrypoint.sh"]
