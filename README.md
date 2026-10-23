# docker-ondrej-php

PHP 7.4-FPM on Debian trixie, built from [Ondřej Surý's](https://packages.sury.org/php/) packages
(php2shell fixes included, hopefully).

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

The image is deliberately minimal: CLI + FPM + the extensions PHP ships with (opcache, pdo, json,
session, sodium, ...). For additional PHP extensions, install them with apt-get in your derived
Dockerfile:

```dockerfile
FROM ghcr.io/nathanadhitya/docker-ondrej-php:7.4
RUN apt-get update \
    && apt-get -y install php7.4-mbstring php7.4-mysql php7.4-curl \
    && rm -rf /var/lib/apt/lists/*
```

## Tags

| Tag | Meaning |
| --- | --- |
| `7.4` | Latest nightly build, moving tag |

The workflow runs every night at **03:00 UTC**, and on every push to `main`, so new
`packages.sury.org` builds land automatically. If sury ever stops publishing `php7.4` for trixie,
the build fails loudly instead of shipping a stale image.

## Local development

```bash
# build
docker build -t docker-ondrej-php:7.4 docker/7.4

# test (boots the image, checks both listeners, issues a real FastCGI request)
./tests/smoke.sh docker-ondrej-php:7.4
```

`tests/smoke.sh` works with either Docker or Podman (Podman is used automatically when no Docker
daemon is reachable).

## CI/CD

`.github/workflows/build.yml` builds the image, runs `tests/smoke.sh` against it, and only then
pushes `ghcr.io/<owner>/docker-ondrej-php:7.4`. Pull requests build and test without publishing.

The GHCR package is private by default — change its visibility in the package settings if you want
anonymous pulls.
