FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG HERMES_REPO_URL=https://github.com/NousResearch/hermes-agent.git
ARG HERMES_REF=latest-release

LABEL hermes.repo_url=$HERMES_REPO_URL
LABEL hermes.ref=$HERMES_REF

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    nodejs \
    npm \
    python3 \
    python3-venv \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -s /bin/bash hermes
USER hermes
WORKDIR /home/hermes

RUN git clone --depth 1 --branch "$HERMES_REF" "$HERMES_REPO_URL" /home/hermes/hermes-agent \
  && python3 -m venv /home/hermes/venv \
  && /home/hermes/venv/bin/pip install --upgrade pip \
  && /home/hermes/venv/bin/pip install -e "/home/hermes/hermes-agent[all]"

ENV PATH=/home/hermes/venv/bin:$PATH
ENV HERMES_HOME=/data
ENV HOME=/home/hermes

WORKDIR /workspace
CMD ["sleep", "infinity"]
