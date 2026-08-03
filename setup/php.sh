#!/usr/bin/env bash
#
# PHP toolchain for Laravel development.
#
# PHP 8.4 is a hard floor: below it, PDO's inTransaction() does not track
# transactions opened via exec(), which breaks Laravel's SQLite IMMEDIATE
# transaction mode. 8.5 is the target, for native
# Pdo\Sqlite::ATTR_TRANSACTION_MODE.

set -eu -o pipefail

PHP_VERSION=8.5

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	ca-certificates apt-transport-https lsb-release gnupg curl sqlite3 direnv

# Debian ships an older PHP, so this pulls from Ondřej Surý's repo, which
# publishes per Debian codename. If this container's base moves to a codename
# Surý has not published yet, apt-get fails loudly rather than silently leaving
# the distro's older PHP in place.
CODENAME="$(lsb_release -sc)"
curl -fsSL https://packages.sury.org/php/apt.gpg |
	sudo gpg --dearmor -o /usr/share/keyrings/deb.sury.org-php.gpg
echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${CODENAME} main" |
	sudo tee /etc/apt/sources.list.d/php.list >/dev/null

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	"php${PHP_VERSION}-cli" \
	"php${PHP_VERSION}-fpm" \
	"php${PHP_VERSION}-sqlite3" \
	"php${PHP_VERSION}-mbstring" \
	"php${PHP_VERSION}-intl" \
	"php${PHP_VERSION}-xml" \
	"php${PHP_VERSION}-curl" \
	"php${PHP_VERSION}-zip" \
	"php${PHP_VERSION}-gd" \
	"php${PHP_VERSION}-bcmath"
# No -opcache or -sodium package: as of 8.5 Surý compiles both into the cli and
# fpm binaries. Asking for them by name fails the build.

# Fail at build time, not at first request, if we did not get what we asked for.
php -r 'exit(version_compare(PHP_VERSION, "8.4", ">=") ? 0 : 1);' ||
	{ echo "FATAL: PHP >= 8.4 required, got $(php -v | head -1)" >&2; exit 1; }
php -r 'exit(extension_loaded("pdo_sqlite") ? 0 : 1);' ||
	{ echo "FATAL: pdo_sqlite missing" >&2; exit 1; }
# sodium signs and verifies the handoff tokens. Normally bundled, but a missing
# one would otherwise only surface at the first sign-in.
php -r 'exit(extension_loaded("sodium") ? 0 : 1);' ||
	{ echo "FATAL: sodium missing" >&2; exit 1; }

curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
sudo php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f /tmp/composer-setup.php

# Caddy — needed to exercise per-tenant subdomain routing and host-scoped
# session cookies locally. Single binary, no apt repo needed.
CADDY_VERSION=2.8.4
curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" -o /tmp/caddy.tar.gz
sudo tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy
rm -f /tmp/caddy.tar.gz

echo 'export PATH=$PATH:/workspace/bin' >>"$HOME/.bashrc"
echo 'eval "$(direnv hook bash)"' >>"$HOME/.bashrc"

sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
