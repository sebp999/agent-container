FROM node:22-bookworm-slim

ARG USER_UID=1000
ARG USER_GID=1000

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/coder \
    SHELL=/bin/bash

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        file \
        git \
        jq \
        less \
        nano \
        procps \
        ripgrep \
        tar \
        unzip \
        vim-tiny \
        xz-utils; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    if getent group "${USER_GID}" >/dev/null; then \
        group_name="$(getent group "${USER_GID}" | cut -d: -f1)"; \
    else \
        groupadd --gid "${USER_GID}" coder; \
        group_name="coder"; \
    fi; \
    if getent passwd "${USER_UID}" >/dev/null; then \
        existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
        if [ "${existing_user}" != "coder" ]; then \
            usermod --login coder --home /home/coder --move-home "${existing_user}"; \
        fi; \
        usermod --gid "${group_name}" --shell /bin/bash coder; \
    else \
        useradd --uid "${USER_UID}" --gid "${group_name}" --create-home --shell /bin/bash coder; \
    fi; \
    mkdir -p /home/coder; \
    chown -R coder:"${group_name}" /home/coder; \
    git config --system --add safe.directory /workspace

RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @opencode/cli; \
    npm cache clean --force

WORKDIR /workspace
USER coder

CMD ["bash"]
