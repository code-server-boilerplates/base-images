# Check the Debian website for the codenames!
ARG buildpackDistro=bullseye
FROM buildpack-deps:${buildpack}

COPY overlay/ /

USER root

# Install code-server as root on /usr/local
ARG cdrVersion=4.0.2
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${cdrVersion} --prefix=/usr/local

# Init Gitpod-styled workspace directory. This is needed to only
# presist files mounted into volumes
RUN mkdir /workspace && touch /workspace/.hello-world \
    # fixes for permission errors due to uid/guid mismatches
    && chown -R coder:coder /workspace && chmod -R 777 /workspace

# Ref: https://computingforgeeks.com/how-to-install-add-apt-repository-on-debian-ubuntu/
RUN apt -y install software-properties-common dirmngr apt-transport-https lsb-release ca-certificates --no-install-recommends

# dumb-init
ARG DUMB_INIT_RELEASE=1.2.5
RUN sudo wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_RELEASE}/dumb-init_${DUMB_INIT_RELEASE}_$(arch) \
    && sudo chmod +x /usr/local/bin/dumb-init