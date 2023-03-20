# syntax=docker/dockerfile:1
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION} as base
ARG PHP_VERSION=8.2

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG="C.UTF-8"

ENV PHP_VERSION=${PHP_VERSION} \
    PHP_MEMORY_LIMIT=128m \
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_MAX_INPUT_VARS=1500 \
    PHP_ASSERT=-1 \
    PHP_XDEBUG_HOST=host.docker.internal \
    PHP_XDEBUG_MODE=off \
    TIDEWAYS_APIKEY="" \
    TIDEWAYS_DAEMON="tcp://tideways-daemon:9135" \
    TIDEWAYS_SAMPLERATE=25

RUN apt-get update && \
    apt-get -y install --no-install-suggests --no-install-recommends \
        software-properties-common \
        apt-transport-https\
        libfcgi-bin \
        ca-certificates \
        curl \
        gnupg2

RUN echo 'deb https://packages.tideways.com/apt-packages-main any-version main' > /etc/apt/sources.list.d/tideways.list && \
    curl -L -sS 'https://packages.tideways.com/key.gpg' | apt-key add -

RUN add-apt-repository ppa:ondrej/php -y && \
    apt-get update

RUN apt-get update && \
    apt-get -y install --no-install-suggests --no-install-recommends \
        ghostscript \
        gifsicle \
        imagemagick \
        jpegoptim \
        openssl \
        optipng \
        pngquant \
        tar \
        unzip \
        webp \
        zip \
        php${PHP_VERSION} \
        php-apcu \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-gd \
        php-igbinary \
        php-imagick \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-readline \
        php-redis \
        php${PHP_VERSION}-xml \
        php-yaml \
        php${PHP_VERSION}-zip \
    && apt-get autoremove \
    && find /var/log -type f -name "*.log" -delete \
    && rm -rf /var/lib/apt/lists/* /var/cache/ldconfig/aux-cache

RUN ln -s /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm

RUN mkdir -p "/run/php/" \
    && chown -R www-data:www-data /run/php/ \
    && chmod 755 /run/php/ \
    && touch /var/log/xdebug.log \
    && chown www-data:www-data /var/log/xdebug.log

# Config files
COPY config/conf.d /etc/php/${PHP_VERSION}/cli/conf.d/
COPY config/conf.d /etc/php/${PHP_VERSION}/fpm/conf.d/
COPY config/fpm/pool.d /etc/php/${PHP_VERSION}/fpm/pool.d/
COPY config/fpm-${PHP_VERSION}/pool.d /etc/php/${PHP_VERSION}/fpm/pool.d/

# Test php-fpm config and php info
RUN php-fpm -tt
RUN php -i

WORKDIR /var/www

FROM base AS php-fpm

COPY fpm /usr/local/bin/

STOPSIGNAL SIGQUIT
EXPOSE 9000

HEALTHCHECK --interval=2s --timeout=5s --retries=10 CMD php-fpm-healthcheck || exit 1
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["php-fpm"]

FROM base AS php-cli

ENV PHP_MEMORY_LIMIT=-1 \
    PHP_MAX_EXECUTION_TIME=-1

COPY cli/docker-php-entrypoint /usr/local/bin/

ENTRYPOINT ["docker-php-entrypoint"]
CMD ["php", "-a"]

FROM php-cli AS php-cron

RUN apt-get update && \
    apt-get -y install --no-install-suggests --no-install-recommends \
      cron \
    && apt-get autoremove \
    && find /var/log -type f -name "*.log" -delete \
    && rm -rf /var/lib/apt/lists/* /var/cache/ldconfig/aux-cache \
    && rm -rf /etc/cron.*/*

WORKDIR /var/www

COPY cron/docker-cron-entrypoint /usr/local/bin/

ENTRYPOINT ["docker-cron-entrypoint"]
CMD ["cron", "-f", "-l", "2"]

FROM php-cli AS php-supervisor

RUN apt-get update && \
    apt-get -y install --no-install-suggests --no-install-recommends \
      supervisor \
    && apt-get autoremove \
    && find /var/log -type f -name "*.log" -delete \
    && rm -rf /var/lib/apt/lists/* /var/cache/ldconfig/aux-cache \
    && rm -rf /etc/cron.*/*

RUN touch /var/run/supervisord.pid \
    && chown www-data:www-data /var/run/supervisord.pid

WORKDIR /var/www

COPY supervisor/docker-supervisor-entrypoint /usr/local/bin/
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

USER www-data

ENTRYPOINT ["docker-supervisor-entrypoint"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

# Dev PHP fpm
FROM php-fpm AS php-fpm-dev

ENV PHP_ASSERT=1 \
    COMPOSER_CACHE_DIR=/.cache/composer/ \
    YARN_CACHE_FOLDER=/.cache/yarn/ \
    npm_config_cache=/.cache/npm/ \
    TERM=xterm-256color

# enable debugging with PhpStorm
ENV PHP_IDE_CONFIG="serverName=localhost"

RUN apt-get update && \
    apt-get -y install --no-install-suggests --no-install-recommends \
      make php${PHP_VERSION}-dev php${PHP_VERSION}-sqlite3 php-pear openssh-client git patch \
    && mkdir -p /tmp/pear/cache \
    && pecl channel-update pecl.php.net \
    && pecl install xdebug-3.2.0 \
    && echo "zend_extension=xdebug.so" > /etc/php/${PHP_VERSION}/mods-available/xdebug.ini \
    && phpenmod xdebug \
    && apt-get -y autoremove --purge make php${PHP_VERSION}-dev php-pear \
    && apt-get autoremove \
    && find /var/log -type f -name "*.log" -delete \
    && rm -rf /root/.pearrc \
    && rm -rf /tmp/pear \
    && rm -rf /var/lib/php/modules/${PHP_VERSION}/cli/disabled_by_maint \
    && rm -rf /var/lib/php/modules/${PHP_VERSION}/fpm/disabled_by_maint \
    && rm -rf /usr/share/php/.registry /usr/share/php/.depdb /usr/share/php/.filemap \
    && rm -rf /usr/share/bug/file \
    && rm -rf /usr/share/doc/file \
    && rm -rf /var/lib/apt/lists/* /var/cache/ldconfig/aux-cache \
    && touch /var/log/xdebug.log \
    && chown www-data:www-data /var/log/xdebug.log

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY dev/scripts /usr/local/bin/
COPY dev/bash /root/

# Dev PHP cli
FROM php-fpm-dev AS php-cli-dev

ENV PHP_MEMORY_LIMIT=-1
ENV PHP_MAX_EXECUTION_TIME=-1

COPY cli/docker-php-entrypoint /usr/local/bin/

ENTRYPOINT ["docker-php-entrypoint"]
CMD ["php", "-a"]

# Dev PHP cron
FROM php-cli-dev AS php-cron-dev

RUN apt-get update && \
    apt-get -y install --no-install-suggests --no-install-recommends \
      cron \
    && apt-get autoremove \
    && find /var/log -type f -name "*.log" -delete \
    && rm -rf /var/lib/apt/lists/* /var/cache/ldconfig/aux-cache \
    && rm -rf /etc/cron.*/*

WORKDIR /var/www

COPY cron/docker-cron-entrypoint /usr/local/bin/

# Disabling the health check of the descendant php-fpm-dev image, since the production php-cron image does neither have a healthcheck.
HEALTHCHECK NONE
ENTRYPOINT ["docker-cron-entrypoint"]
CMD ["cron", "-f", "-l", "2"]