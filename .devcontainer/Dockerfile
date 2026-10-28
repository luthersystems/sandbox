# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.208.0/containers/debian/.devcontainer/base.Dockerfile

# [Choice] Debian version (use bullseye or stretch on local arm64/Apple Silicon): bullseye, buster, stretch
ARG VARIANT="buster"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# ** [Optional] Uncomment this section to install additional packages. **
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends time

# Run the container as the base image's non-root vscode user, the same user
# devcontainer.json's remoteUser already connects as (Trivy DS-0002). The
# devcontainer features install as root in their own layer and then switch
# back to this user; vscode has passwordless sudo for anything that needs root.
USER vscode
