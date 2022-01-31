# Check the Debian website for the codenames! You can also override this via
# build arguments, through please update the Dockerfile and the scripts in overlay/usr/local/bin
# before proceeding!
ARG buildpackDistro=bullseye
FROM buildpack-deps:${buildpackDistro}

LABEL org.opencontainers.image.documentation="https://csb-docs.community-lores.gq"

COPY overlay/ /

USER root

# Install code-server as root on /usr/local
ARG cdrVersion=4.0.2

# Ref: https://computingforgeeks.com/how-to-install-add-apt-repository-on-debian-ubuntu/
# Install packages and do some language prep stuff
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/coder/.local/bin
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${cdrVersion} --prefix=/usr/local \
    && /usr/local/bin/install-packages \
      dumb-init \
      zsh \
      htop \
      locales \
      man \
      nano \
      git \
      git-lfs \
      procps \
      openssh-client \
      sudo \
      vim.tiny \
      lsb-release \
      gpg \
  && git lfs install \
  && sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen && locale-gen \
  && rm -rfv /root/.cache

RUN adduser --gecos '' --disabled-password coder && \
  echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd \
  && ARCH="$(dpkg --print-architecture)" && \
    curl -fsSL "https://github.com/boxboat/fixuid/releases/download/v0.5/fixuid-0.5-linux-$ARCH.tar.gz" | tar -C /usr/local/bin -xzf - && \
    chown root:root /usr/local/bin/fixuid && \
    chmod 4755 /usr/local/bin/fixuid && \
    mkdir -p /etc/fixuid && \
    printf "user: coder\ngroup: coder\n" > /etc/fixuid/config.yml

# Init Gitpod-styled workspace directory. This is needed to only presist files mounted into volumes
RUN mkdir /workspace && touch /workspace/.hello-world \
    # fixes for permission errors due to uid/guid mismatches
    && chown -Rv coder:coder /workspace && chmod -R 777 /workspace
VOLUME [ "/workspace" ]

# This way, if someone sets $DOCKER_USER, docker-exec will still work as
# the uid will remain the same. note: only relevant if -u isn't passed to
# docker-run.
USER 1000
ENV USER=coder LANG=en_US.UTF-8
WORKDIR /home/coder
EXPOSE 8080

COPY --chown=coder:coder docker/rclone-tasks.json /home/coder/.local/share/code-server/User/tasks.json

ENTRYPOINT [ "/usr/local/bin/code-server-launchpad.sh" ]
CMD [ "start" ]