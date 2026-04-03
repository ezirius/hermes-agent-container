FROM debian:13.4

ARG DEBIAN_FRONTEND=noninteractive
ARG HERMES_REPO_URL=https://github.com/NousResearch/hermes-agent.git
ARG HERMES_REF=latest-release

LABEL hermes.repo_url=$HERMES_REPO_URL
LABEL hermes.ref=$HERMES_REF

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    cmake \
    ffmpeg \
    g++ \
    gcc \
    git \
    libffi-dev \
    libolm-dev \
    make \
    nodejs \
    npm \
    python3 \
    python3-dev \
    python3-pip \
    ripgrep \
  && rm -rf /var/lib/apt/lists/*

COPY config/patches /tmp/hermes-patches
COPY config/containers/entrypoint.sh /usr/local/bin/hermes-entrypoint.sh

RUN chmod +x /usr/local/bin/hermes-entrypoint.sh \
  && if ! id hermes >/dev/null 2>&1; then useradd -m -s /bin/bash hermes; fi

WORKDIR /home/hermes

RUN git clone --depth 1 --branch "$HERMES_REF" "$HERMES_REPO_URL" /home/hermes/hermes-agent \
  && python3 /tmp/hermes-patches/apply-hermes-mautrix-migration.py \
  && python3 /tmp/hermes-patches/apply-hermes-host-agents-context.py \
  && python3 -m pip install -e "/home/hermes/hermes-agent[all]" --break-system-packages \
  && cd /home/hermes/hermes-agent \
  && npm install \
  && npx playwright install --with-deps chromium \
  && cd /home/hermes/hermes-agent/scripts/whatsapp-bridge \
  && npm install \
  && rm -rf /home/hermes/.hermes \
  && mkdir -p /opt/data \
  && ln -s /opt/data /home/hermes/.hermes \
  && chown -R hermes:hermes /home/hermes /opt/data

ENV HERMES_HOME=/opt/data
ENV HOME=/home/hermes

USER hermes
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/hermes-entrypoint.sh"]
