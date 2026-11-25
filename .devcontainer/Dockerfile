# Lab toolbox: everything the Makefiles need, nothing required on the host except Docker.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG KUBECTL_VERSION=v1.36.2
ARG HELM_VERSION=v4.3.2
ARG KIND_VERSION=v0.33.0
ARG K9S_VERSION=v0.51.0

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      make jq openssl curl ca-certificates netcat-openbsd dnsutils bash-completion tmux \
 && rm -rf /var/lib/apt/lists/*

COPY install-tools.sh /tmp/install-tools.sh
RUN KUBECTL_VERSION=$KUBECTL_VERSION HELM_VERSION=$HELM_VERSION KIND_VERSION=$KIND_VERSION K9S_VERSION=$K9S_VERSION \
    bash /tmp/install-tools.sh && rm /tmp/install-tools.sh \
 && kubectl completion bash > /etc/bash_completion.d/kubectl \
 && helm completion bash > /etc/bash_completion.d/helm \
 && kind completion bash > /etc/bash_completion.d/kind
