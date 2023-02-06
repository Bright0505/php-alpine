FROM alpine:3.16

ENV PHP_VERSION 8.1.13
ENV PHP_SHA256 b15ef0ccdd6760825604b3c4e3e73558dcf87c75ef1d68ef4289d8fd261ac856
ENV GPG_KEYS F1F692238FBC1666E5A5CCD4199F9DFEF6FFBAFD
ENV COMPOSER_VERSION 2.3.10

ENV PHP_PACKET bcmath gd intl mysqli opcache pdo_mysql zip

ENV PHPIZE_DEPS autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkgconf re2c 

# persistent / runtime deps
RUN apk add --no-cache \
		ca-certificates \
		curl \
		tar \
		xz \
		openssl \
	#install gd packge
		libpng-dev \
		zlib-dev \
	#install intl packge
		icu-dev \
	#install zip packge
		libzip-dev 

ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
	mkdir -p /var/log/php

ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

ENV PHP_URL="https://www.php.net/distributions/php-"$PHP_VERSION".tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-"$PHP_VERSION".tar.xz.asc"

RUN set -eux; \
	apk add --no-cache --virtual .fetch-deps gnupg; \
	mkdir -p /usr/src; \
	cd /usr/src; \
	curl -fsSL -o php.tar.xz "$PHP_URL"; \
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi; \
	if [ -n "$PHP_ASC_URL" ]; then \
		curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
		export GNUPGHOME="$(mktemp -d)"; \
		for key in $GPG_KEYS; do \
			gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
		done; \
		gpg --batch --verify php.tar.xz.asc php.tar.xz; \
		gpgconf --kill all; \
		rm -rf "$GNUPGHOME"; \
	fi; \
	apk del --no-network .fetch-deps

COPY ./extension/docker-php-* /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-php-*

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		argon2-dev \
		coreutils \
		curl-dev \
		gnu-libiconv-dev \
		libsodium-dev \
		libxml2-dev \
		linux-headers \
		oniguruma-dev \
		openssl-dev \
		readline-dev \
		sqlite-dev \
		imagemagick-dev \
		libtool \
	; \
# make sure musl's iconv doesn't get used (https://www.php.net/manual/en/intro.iconv.php)
	rm -vf /usr/include/iconv.h; \
# PHP < 8 doesn't know to look deeper for GNU libiconv: https://github.com/php/php-src/commit/b480e6841ecd5317faa136647a2b8253a4c2d0df
	ln -sv /usr/include/gnu-libiconv/*.h /usr/include/; \
	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS"; \
	docker-php-source extract; \
	cd /usr/src/php; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		--enable-option-checking=fatal \
		--with-mhash \
		--with-pic \
		--enable-ftp \
		--enable-mbstring \
		--enable-mysqlnd \
		--with-password-argon2 \
		--with-sodium=shared \
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		--with-curl \
		--with-iconv=/usr \
		--with-openssl \
		--with-readline \
		--with-zlib \
		--disable-phpdbg \
		--with-pear \
		$(test "$gnuArch" = 's390x-linux-musl' && echo '--without-pcre-jit') \
		--disable-cgi \
		--enable-fpm \
		--with-fpm-user=nginx \
		--with-fpm-group=nginx \
	; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find \
		/usr/local \
		-type f \
		-perm '/0111' \
		-exec sh -euxc ' \
			strip --strip-all "$@" || : \
		' -- '{}' + \
	; \
	make clean; \
	cd /; \
	docker-php-source delete; \
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	# install imagick
	pecl install imagick; \
    docker-php-ext-enable imagick; \
	apk add --no-cache $runDeps; \
	apk del --no-network .build-deps; \
	pecl update-channels; \
	rm -rf /tmp/pear ~/.pearrc

# sodium was built as a shared module (so that it can be replaced later if so desired), so let's enable it too (https://github.com/docker-library/php/issues/598)
RUN docker-php-ext-enable sodium

# Install Composer
RUN curl -o /tmp/composer-setup.php https://getcomposer.org/installer; \
	curl -o /tmp/composer-setup.sig https://composer.github.io/installer.sig; \
	php -r "if (hash('SHA384', file_get_contents('/tmp/composer-setup.php')) !== trim(file_get_contents('/tmp/composer-setup.sig'))) { unlink('/tmp/composer-setup.php'); echo 'Invalid installer' . PHP_EOL; exit(1); }"; \
	php /tmp/composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer --version=${COMPOSER_VERSION}; \
	rm -rf /tmp/composer-setup.php

ENTRYPOINT ["docker-php-entrypoint"]

#install php packet
RUN	docker-php-ext-install -j$(nproc) $PHP_PACKET

# Override stop signal to stop process gracefully
STOPSIGNAL SIGQUIT

# Copy php config
COPY ./php/php.ini /usr/local/etc/php/php.ini
COPY ./php/php-fpm.conf /usr/local/etc/php-fpm.conf


WORKDIR /www

# Create nginx user and group
RUN set -eux; addgroup -S nginx; adduser -S nginx -G nginx
RUN chown -R nginx:nginx /www

EXPOSE 9000

CMD ["php-fpm"]
