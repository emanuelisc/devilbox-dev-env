# PHP 8.3 for devilbox mass-vhosting.
#
# devilbox/php-fpm images stop at 8.2 (last tag 8.2-work-0.151, 2023-02-03), so
# anything newer has to be built here. This image mimics the devilbox conventions
# the rest of the stack relies on:
#   - /shared/httpd            same path as the other PHP containers (SCRIPT_FILENAME)
#   - /etc/php-custom.d        user *.ini overrides   (cfg/php-ini-8.3)
#   - /etc/php-fpm-custom.d    user *.conf overrides  (cfg/php-fpm-8.3)
#   - /etc/bashrc-devilbox.d   user shell snippets    (bash/)
#
# It also ships the "work" toolchain (node/npm/yarn, wp-cli, composer, git, ...)
# so `./shell.sh php83` is as usable as `./shell.sh php71`.
FROM php:8.3-fpm-bookworm

ARG NODE_VERSION=22.20.0
ARG WP_CLI_VERSION=2.12.0

ADD --chmod=0755 \
    https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    /usr/local/bin/

RUN install-php-extensions \
      bcmath calendar exif gd intl mysqli opcache pcntl \
      pdo_mysql pdo_pgsql redis soap sockets xsl zip \
      @composer

RUN install-php-extensions imagick mongodb xdebug

# CLI toolchain. Roughly the subset of devilbox/php-fpm:*-work that day to day
# work actually needs; anything project specific is better installed per project.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash-completion \
      ca-certificates \
      curl \
      default-mysql-client \
      git \
      gnupg \
      iproute2 \
      iputils-ping \
      jq \
      less \
      make \
      nano \
      openssh-client \
      patch \
      postgresql-client \
      procps \
      rsync \
      socat \
      sudo \
      unzip \
      vim \
      wget \
      xz-utils \
      zip \
 && rm -rf /var/lib/apt/lists/*

# Node.js from the official tarball (nodesource/apt lags behind and pulls in a
# second package manager). Arch is derived from the build host so the same
# Dockerfile builds on Apple Silicon and on x86.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) node_arch='x64' ;; \
      arm64) node_arch='arm64' ;; \
      *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
      --exclude='*/CHANGELOG.md' --exclude='*/LICENSE' --exclude='*/README.md'; \
    rm /tmp/node.tar.xz; \
    npm install -g --no-audit --no-fund yarn pnpm; \
    npm cache clean --force; \
    node --version; npm --version; yarn --version

RUN curl -fsSL -o /usr/local/bin/wp \
      "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
 && chmod +x /usr/local/bin/wp

# Devilbox-style config drop-in dirs. Only *.ini / *.conf are loaded, which is
# why the shipped `-default` / `-xdebug` example files stay inert.
RUN mkdir -p /etc/php-custom.d /etc/php-fpm-custom.d /etc/bashrc-devilbox.d \
 && echo 'include=/etc/php-fpm-custom.d/*.conf' >> /usr/local/etc/php-fpm.conf
ENV PHP_INI_SCAN_DIR=":/etc/php-custom.d"

# devilbox user, so `docker compose exec --user devilbox` and ./shell.sh behave
# the same here as in the stock devilbox images. UID/GID are re-mapped at
# runtime from NEW_UID/NEW_GID (see entrypoint.sh).
RUN groupadd -g 1000 devilbox \
 && useradd -u 1000 -g devilbox -m -s /bin/bash devilbox \
 && echo 'devilbox ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/devilbox \
 && chmod 0440 /etc/sudoers.d/devilbox

# Shell environment, mirroring what devilbox/php-fpm puts into ~/.bashrc:
# global composer/yarn bins on PATH and sourcing of /etc/bashrc-devilbox.d/*.sh
# (bind-mounted from the devilbox `bash/` directory). The ~/.bashrc hook has to
# come last: Debian's default ~/.bashrc resets PS1, so anything earlier (e.g.
# /etc/bash.bashrc) would be overwritten again.
COPY profile-devilbox.sh /etc/profile.d/zzz-devilbox.sh
COPY bashrc-devilbox.sh /etc/bash-devilbox
RUN chmod 0644 /etc/profile.d/zzz-devilbox.sh /etc/bash-devilbox \
 && for f in /etc/skel/.bashrc /root/.bashrc /home/devilbox/.bashrc; do \
        printf '\n# [Devilbox] container shell environment\n. /etc/bash-devilbox\n' >> "$f"; \
    done \
 && chown devilbox:devilbox /home/devilbox/.bashrc

WORKDIR /shared/httpd

COPY entrypoint.sh /usr/local/bin/devilbox-entrypoint.sh
RUN chmod +x /usr/local/bin/devilbox-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/devilbox-entrypoint.sh"]
CMD ["php-fpm"]
