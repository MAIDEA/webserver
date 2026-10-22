# AGENTS.md

## Purpose
Docker images (`maidea/webserver` on Docker Hub) that serve a PHP app mounted at `/src` with Apache + mod_php.
There is no app code in this repo. `README.md` is for image users (public, also shown on Docker Hub);
maintainer notes go in `MAINTAINING.md`. The images are offered as-is, best effort (`LICENSE`: all rights reserved).

## Layout
- `Dockerfile`: PHP 8.3/8.4 images. Stages: `mpdecimal` (checksum-verified libmpdec build), `base`, `dev`, `prod` (default target).
  PHP extensions are installed with `install-php-extensions` (mlocati/docker-php-extension-installer, pinned).
- `config/php/*.ini`, `config/apache/*.conf`: copied into the images; `common.ini` is shared, the rest is per target.
- `legacy/<php>-<variant>/`: frozen Dockerfiles for PHP 5.6 and 7.4, kept buildable for internal projects. Change only to keep them building or secure.
- `legacy/php*-base/`: official docker-library recipes for PHP 5.6/7.4 plus `patches/` (CVE-2026-109618/109619 backports); built locally first via
  `prebuild` in `matrix.json`, as `maidea-local/php:*` (never pushed). Edit only lines marked `maidea:`.
- `matrix.json`: single source of truth for every published image (context, target, build args, tags, smoke-test kind).
- `scripts/build.sh`: builds from `matrix.json` (`--smoke`, `--push`). `tests/smoke.sh`: checks a built image through a running container.

## Workflows
```sh
scripts/build.sh --smoke prod-8.4    # build + smoke test one image, no push
scripts/build.sh --smoke             # all images
```
Build for `linux/amd64` only (wkhtmltopdf is an amd64 .deb). Do not add `--platform` to `FROM` lines.

## Rules
- Keep PECL extension versions pinned (decimal 2.x breaks the API used by apps). PHP patch versions float on purpose.
- Downloads outside apt/PECL are checksum-verified (mpdecimal, wkhtmltopdf); keep it that way when bumping versions.
- Adding a PHP extension: add it to the `install-php-extensions` list, then check it in `tests/smoke.sh` if apps depend on it.
- New image or tag: add it to `matrix.json`; tags are never renamed or removed, since consumers pull them.
- Prod hardening must stay: `expose_php=Off`, `register_argc_argv=Off`, Apache `ServerTokens Prod`, loopback-only health check on `127.0.0.1:8081`.
- Changing any behaviour a user can see (ini values, env vars, included tools): update `README.md` in the same change.
- Verify changes with `scripts/build.sh --smoke <id>` before pushing images.
