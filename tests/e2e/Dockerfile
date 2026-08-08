FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    sudo curl git acl python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash -G sudo dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 440 /etc/sudoers.d/dev

RUN mkdir -p /var/www/vhosts/test-project \
    && chown dev:dev /var/www/vhosts /var/www/vhosts/test-project

RUN groupadd -f www-data

USER dev
WORKDIR /home/dev
