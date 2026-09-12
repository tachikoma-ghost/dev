FROM mcr.microsoft.com/devcontainers/typescript-node

WORKDIR /home/node
COPY setup /setup

USER node

RUN USER=node /setup/sshd.sh
RUN /setup/tmux.sh
RUN /setup/terminfo.sh
RUN /setup/bash.sh
RUN /setup/nvim.sh
RUN /setup/agent.sh
RUN /setup/php.sh
#RUN /setup/icp.sh
#RUN /setup/rust.sh
RUN /setup/section3.sh
RUN /setup/signalshell.sh

# Rootless Docker-in-Docker. Needs the security_opt block in
# docker-compose.yml, and section3 above to start the daemon: dind.sh
# declares it as a service in ~/.config/section3/conf.d/. See README.md.
RUN /setup/dind.sh

ENTRYPOINT ["/bin/bash", "-c", "if [ -f /workspace/init.sh ]; then /workspace/init.sh; else sleep infinity; fi"]
