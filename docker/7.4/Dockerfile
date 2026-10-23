FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VERSION=7.4

# Add Ondřej Surý's PHP repository
RUN apt-get update \
    && apt-get -y --no-install-recommends install lsb-release ca-certificates curl \
    && curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb \
    && dpkg -i /tmp/debsuryorg-archive-keyring.deb \
    && rm -f /tmp/debsuryorg-archive-keyring.deb \
    && echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    && apt-get update

# Install PHP 7.4 (CLI + FPM)
RUN apt-get -y --no-install-recommends install \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-common" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf "/usr/sbin/php-fpm${PHP_VERSION}" /usr/local/bin/php-fpm

# Two listen endpoints:
#   - unix socket /run/php/php7.4-fpm.sock  (default "www" pool)
#   - TCP 9000                              ("tcp" pool, ondemand)
RUN printf '%s\n' \
        '[tcp]' \
        'user = www-data' \
        'group = www-data' \
        'listen = 9000' \
        'pm = ondemand' \
        'pm.max_children = 10' \
        'pm.process_idle_timeout = 10s' \
        'pm.max_requests = 500' \
        'catch_workers_output = yes' \
        > "/etc/php/${PHP_VERSION}/fpm/pool.d/tcp.conf" \
    && sed -i \
        -e 's|^error_log = .*|error_log = /proc/self/fd/2|' \
        -e 's|^;\?daemonize = .*|daemonize = no|' \
        "/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"

# Fail the build if the repo hands us anything but the PHP we asked for,
# or if the FPM config does not parse.
RUN php --version \
    && php -r 'exit(strpos(PHP_VERSION, getenv("PHP_VERSION") . ".") === 0 ? 0 : 1);' \
    && "php-fpm${PHP_VERSION}" -t

WORKDIR /var/www/html

EXPOSE 9000
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["php", "-r", "$s = @fsockopen('127.0.0.1', 9000, $errno, $errstr, 2); if (!$s) { fwrite(STDERR, \"php-fpm is not accepting connections on 9000\\n\"); exit(1); } fclose($s);"]

CMD ["php-fpm7.4"]
