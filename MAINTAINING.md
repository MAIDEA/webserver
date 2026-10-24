# Maintaining the images

Notes for maintainers. Image usage is documented in [README.md](README.md).

## Repository layout

```
Dockerfile          PHP 8.3/8.4 images; build targets prod (default) and dev
config/             PHP ini and Apache config copied into the images
legacy/php*/        end-of-life PHP versions (5.6, 7.4): Debian 12 + Sury's PHP packages, targets prod and dev
matrix.json         every published image: build context, target, build args, tags
scripts/build.sh    builds images from matrix.json (used by CI and locally)
scripts/*-images.sh decide what CI builds: changed-images.sh (per change), outdated-images.sh (daily)
tests/smoke.sh      checks an image through a running container
.github/workflows/  CI: build.yml (build, test, push) and upstream-check.yml (daily rebuilds)
```

## Building locally

```sh
scripts/build.sh --smoke prod-8.4           # build and smoke-test one image (ids are in matrix.json)
scripts/build.sh --smoke --push prod-8.4    # ... and push all its tags (docker login first)
scripts/build.sh --smoke                    # all images
```

Images are built for `linux/amd64`, also on Apple Silicon (through emulation, slower).
`build.sh` always pulls fresh base images and fails if the built PHP version differs from its source
(the official php image, or for legacy images the current Sury package, whose version it pins and records).
Immutable tags are never overwritten: when the name already exists on Docker Hub, `build.sh` adds `.2`, `.3`, ….

## Versions

* **PHP patch versions are not pinned:** a rebuild picks up the latest patch release of the PHP minor version set in `matrix.json`.
* **PECL extension versions are pinned** (`ARG`s in the `Dockerfile`, overridable per image in `matrix.json`).
  Do not unpin them: e.g. an unpinned decimal installs 2.x, which breaks the API used by existing apps.
* Downloads outside apt and PECL are checksum-verified (mpdecimal, wkhtmltopdf); keep it that way when bumping versions.

## Changes

`master` is the only branch. Maintainers (repository admins) push to it directly; a push publishes the changed images
after they pass the smoke tests (see [CI](#ci)). Pull requests are optional, e.g. to test a change in CI without publishing.
A ruleset requires pull requests and the `result` check for everyone else, and blocks force pushes and deletion;
admins bypass it.

The old per-version branches and tags are preserved as `archive/branch/*` and `archive/tag/*` tags.

## CI

* `build.yml`: pull requests build and smoke-test the affected images; pushes to `master` also publish them.
  Manual runs take image ids (or `all`) and an optional push. `scripts/changed-images.sh` decides what is affected:
  * an image's own files, or its entry in `matrix.json`: that image
  * `scripts/build.sh`, `scripts/php-package-version.sh`, `build.yml`: every image in pull requests;
    when publishing, the images that track upstream (all current images)
  * `tests/`: every image in pull requests; when publishing, nothing is rebuilt and the published images are smoke-tested
  * docs: nothing
* `upstream-check.yml`: daily, rebuilds and publishes images whose sources have changed (`scripts/outdated-images.sh`):
  the base image (`org.opencontainers.image.base.digest` label set by `build.sh`) or, for legacy images,
  the Sury PHP package (`hr.maidea.php-package` label).
* Requires the repository secret `DOCKERHUB_TOKEN` (Docker Hub access token, read & write) and the variable `DOCKERHUB_USERNAME`.

## Legacy images

* `legacy/php5.6` and `legacy/php7.4` install PHP from [packages.sury.org](https://packages.sury.org/php/) on Debian 12
  (`debian:bookworm-slim`). Sury's packages carry backported security fixes; the Dockerfiles refuse package versions
  older than the CVE-2026-109618/109619 fix (`PHP_PACKAGE_MIN`).
* They reproduce the earlier images built from the official php recipe: same extensions (`extensions.txt` = Debian ini
  files to load, `modules.txt` = expected `php -m`, checked at build time by `php-modules-check`), settings, tools and
  Apache setup, with PHP reading `/usr/local/etc/php` (`PHPRC`, `PHP_INI_SCAN_DIR`) instead of Debian's `/etc/php`.
* Extension versions outside the PHP package (apcu, mcrypt, xdebug) come from Sury and are checked to stay within a minor version.
* Keep them like this: change only what keeps them building, secure or compatible with the apps that use them.
