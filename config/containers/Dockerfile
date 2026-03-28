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
    libolm-dev \
    nodejs \
    npm \
    python3 \
    python3-venv \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

COPY config/patches /tmp/hermes-patches

RUN if ! id hermes >/dev/null 2>&1; then useradd -m -s /bin/bash hermes; fi
USER hermes
WORKDIR /home/hermes

RUN git clone --depth 1 --branch "$HERMES_REF" "$HERMES_REPO_URL" /home/hermes/hermes-agent \
  && python3 /tmp/hermes-patches/apply-hermes-matrix-sync-diagnostics.py \
  && python3 /tmp/hermes-patches/apply-hermes-matrix-store-home.py \
  && python3 -m venv /home/hermes/venv \
  && /home/hermes/venv/bin/pip install --upgrade pip \
  && /home/hermes/venv/bin/pip install -e "/home/hermes/hermes-agent[all]" \
  && /home/hermes/venv/bin/pip install 'matrix-nio[e2e]' \
  && rm -rf /home/hermes/.hermes \
  && ln -s /data /home/hermes/.hermes

ENV PATH=/home/hermes/venv/bin:$PATH
ENV HERMES_HOME=/data
ENV HOME=/home/hermes

WORKDIR /workspace
CMD ["sleep", "infinity"]
