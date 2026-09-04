FROM mcr.microsoft.com/devcontainers/typescript-node

WORKDIR /home/node
COPY setup /setup

USER node

RUN USER=node /setup/sshd.sh
RUN /setup/nvim.sh
RUN USER=node /setup/bash.sh
RUN /setup/agent.sh
#RUN /setup/php.sh
#RUN /setup/icp.sh
#RUN /setup/rust.sh
RUN /setup/tmux.sh
RUN /setup/terminfo.sh
RUN /setup/section3.sh
RUN /setup/signalshell.sh

# Rootless Docker-in-Docker, for tools that run their own containers (Laravel
# Sail and friends). Enabling it also needs the security_opt block in
# docker-compose.yml and the `dind` service in /workspace/section3.yml — see
# the header of setup/dind.sh.
#RUN /setup/dind.sh

#CMD [ "sleep", "infinity" ]
ENTRYPOINT ["/bin/bash", "-c", "if [ -f /workspace/init.sh ]; then /workspace/init.sh; else sleep infinity; fi"]
