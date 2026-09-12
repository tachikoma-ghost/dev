FROM mcr.microsoft.com/devcontainers/typescript-node

# The build has no controlling tty; without this debconf tries Dialog,
# Readline and Teletype in turn and logs each failure before falling back
# to Noninteractive anyway. ARG rather than ENV so it applies to the build
# only and does not leak into the running container, where an interactive
# apt should still be allowed to ask.
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /home/node
COPY setup /setup

USER node

RUN USER=node /setup/sshd.sh
RUN /setup/tmux.sh
RUN /setup/terminfo.sh
RUN /setup/bash.sh
RUN /setup/nvim.sh
RUN /setup/agent.sh
#RUN /setup/icp.sh
#RUN /setup/rust.sh
#RUN /setup/section3.sh
#RUN /setup/signalshell.sh
#RUN /setup/dind.sh  # requires section3 to start the daemon automatically. See README.md

ENTRYPOINT ["/bin/bash", "-c", "if [ -f /workspace/init.sh ]; then /workspace/init.sh; else sleep infinity; fi"]
