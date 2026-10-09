# Base image knob (auth.docker.io outage 2026-10): lib.sh forwards
# E2E_BASE_IMAGE as --build-arg BASE_IMAGE (ARG before FROM). CI pulls
# through the Google Docker Hub mirror so a 504 on the anonymous token
# endpoint cannot kill every suite at metadata resolution; the default
# keeps local runs on docker.io.
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# git channel (issue #118): 'distro' (default) keeps the base image's apt
# git — 2.43 on noble, close to the documented oldest baseline distros
# (Debian 12: 2.30, Ubuntu 22.04: 2.34). 'latest' upgrades to the current
# git-core PPA release, resolved at BUILD time: the weekly cron burn-in
# therefore catches new-upstream-git behavior drift without a manual pin
# (same drift design as the opencode version resolution). The #116
# unreadable-CWD fatal only existed on git >= 2.55 — invisible at the
# distro floor the suite used to pin. lib.sh forwards E2E_GIT_CHANNEL
# as --build-arg GIT_CHANNEL=...
ARG GIT_CHANNEL=distro

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    sudo curl git acl python3 ca-certificates nodejs npm \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$GIT_CHANNEL" = "latest" ]; then \
        apt-get update -qq \
        && apt-get install -y --no-install-recommends software-properties-common \
        && add-apt-repository -y ppa:git-core/ppa \
        && apt-get update -qq \
        && apt-get install -y --no-install-recommends git \
        && rm -rf /var/lib/apt/lists/* \
        && git --version; \
    fi

RUN useradd -m -s /bin/bash -G sudo dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 440 /etc/sudoers.d/dev

RUN mkdir -p /var/www/vhosts/test-project \
    && chown dev:dev /var/www/vhosts /var/www/vhosts/test-project

RUN groupadd -f www-data

USER dev
WORKDIR /home/dev
