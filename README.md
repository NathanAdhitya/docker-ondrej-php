# docker-ondrej-php

PHP 7.4-FPM on Debian Trixie, built from [Ondřej Surý's](https://packages.sury.org/php/) packages
(php2shell fixes included, hopefully). Partially AI-assisted.

Nightly CI/CD. Published to GHCR as `:7.4`.

> If it works, it aint stupid  
> \- someone, from long time ago

## Usage

```bash
docker pull ghcr.io/nathanadhitya/docker-ondrej-php:7.4
```

The image starts PHP-FPM in the foreground and listens on **both**:

| Endpoint | Pool | Notes |
| --- | --- | --- |
| `unix:/run/php/php7.4-fpm.sock` | `www` (default) | For nginx sharing a volume/pod |
| `0.0.0.0:9000` | `tcp` | For nginx in a separate container |

```bash
docker run --rm -p 9000:9000 ghcr.io/nathanadhitya/docker-ondrej-php:7.4
```

The image is deliberately minimal: CLI + FPM + common extensions from php{version}-common. For
additional PHP extensions, install them with apt-get in your derived Dockerfile:

```dockerfile
FROM ghcr.io/nathanadhitya/docker-ondrej-php:7.4
RUN apt-get update \
    && apt-get -y install php7.4-mbstring php7.4-mysql php7.4-curl \
    && rm -rf /var/lib/apt/lists/*
```

## Configuration overrides

The image follows Debian's layout: one config tree per SAPI, and FPM pools live in `pool.d`. There
is **no `php-fpm.d`** here — that directory only exists in the official `php` Docker images.

| What | Path in this image | Official `php` image |
| --- | --- | --- |
| `php.ini` (FPM) | `/etc/php/7.4/fpm/php.ini` | `/usr/local/etc/php/php.ini` |
| `php.ini` (CLI) | `/etc/php/7.4/cli/php.ini` | same file |
| Drop-in settings (FPM) | `/etc/php/7.4/fpm/conf.d/*.ini` | `/usr/local/etc/php/conf.d` |
| Drop-in settings (CLI) | `/etc/php/7.4/cli/conf.d/*.ini` | same directory |
| Extension definitions | `/etc/php/7.4/mods-available/*.ini` | n/a |
| FPM pools | `/etc/php/7.4/fpm/pool.d/*.conf` (`www.conf`, `tcp.conf`) | `/usr/local/etc/php-fpm.d` |
| FPM master config | `/etc/php/7.4/fpm/php-fpm.conf` (`include=pool.d/*.conf`) | `php-fpm.conf` |

CLI and FPM are separate trees: a setting added under `fpm/` does not affect `php`, `composer` or
`artisan`. Add it to both trees (or to a pool) if you need parity.

Packaged defaults worth knowing: FPM `memory_limit=128M`, CLI `memory_limit=-1`, `date.timezone`
unset.

### Derived image

```dockerfile
FROM ghcr.io/nathanadhitya/docker-ondrej-php:7.4

# Extra php.ini directives, loaded after the packaged ones
COPY 99-custom.ini /etc/php/7.4/fpm/conf.d/99-custom.ini

# Same, for the CLI SAPI
COPY 99-custom.ini /etc/php/7.4/cli/conf.d/99-custom.ini

# Replace the unix-socket pool (use tcp.conf for the :9000 pool)
COPY www.conf /etc/php/7.4/fpm/pool.d/www.conf

# Replace php.ini wholesale (you lose the packaged defaults)
COPY php.ini /etc/php/7.4/fpm/php.ini
```

Installing an extension (`apt-get install php7.4-mbstring`) creates the `conf.d` symlinks in both
trees for you, and the extension is loaded on the next start.

### Runtime mounts

Mount individual files and keep them read-only:

```bash
docker run --rm -p 9000:9000 \
  -v "$PWD/99-custom.ini:/etc/php/7.4/fpm/conf.d/99-custom.ini:ro,Z" \
  -v "$PWD/www.conf:/etc/php/7.4/fpm/pool.d/www.conf:ro,Z" \
  ghcr.io/nathanadhitya/docker-ondrej-php:7.4
```

```yaml
services:
  php:
    image: ghcr.io/nathanadhitya/docker-ondrej-php:7.4
    volumes:
      - ./99-custom.ini:/etc/php/7.4/fpm/conf.d/99-custom.ini:ro,Z
      - ./www.conf:/etc/php/7.4/fpm/pool.d/www.conf:ro,Z
```

The `:Z` suffix relabels the file for SELinux hosts; drop it elsewhere.

### Precedence

1. `php_admin_value[...]` in the pool — wins, and cannot be overridden at runtime.
2. `conf.d/*.ini` — loaded alphabetically, last file wins (`99-` beats `20-`).
3. `php.ini` — base values.

The `www` and `tcp` pools are independent: a `php_admin_value` in `www.conf` does not apply to
requests served on `:9000`. Set it in both pools if both are used.

### Gotchas

- Mounting a **directory** over `conf.d` hides the packaged extension inis — opcache, pdo and
  friends stop loading. Mount single files, or `COPY` them in a derived image.
- Mounting a directory over `pool.d` hides `www.conf` and `tcp.conf`, so one or both listeners
  disappear.
- `pool.d` only reads `*.conf`; an `.ini` file dropped there is silently ignored.
- Config is read at startup: restart the container after changing a mounted file. An extension
  installed at runtime is not loaded until the next start.
- Validate before restarting: `docker run --rm -v ... <image> php-fpm7.4 -t`.

### Verify

```bash
docker exec <container> php --ini                      # CLI: loaded php.ini + conf.d
docker exec <container> php-fpm7.4 -i | grep -E 'Loaded Configuration|Scan this dir'
docker exec <container> php-fpm7.4 -tt                 # dump parsed pools
```

## Tags

| Tag | Meaning |
| --- | --- |
| `7.4` | Latest nightly build, moving tag |

The workflow runs every night at **03:00 UTC**, and on every push to `main`, so new
`packages.sury.org` builds land automatically. If sury ever stops publishing `php7.4` for trixie,
the build fails loudly instead of shipping a stale image.
