# Maintaining the images

Notes for maintainers. Image usage is documented in [README.md](README.md).

## Repository layout

```
Dockerfile          PHP 8.3/8.4 images; build targets prod (default) and dev
config/             PHP ini and Apache config copied into the images
legacy/             Dockerfiles for PHP 5.6 and 7.4 (security fixes only)
legacy/php*-base/   official php image recipes for 5.6/7.4, rebuilt with security patches
matrix.json         every published image: build context, target, build args, tags
scripts/build.sh    builds images from matrix.json (used by CI and locally)
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
`build.sh` always pulls fresh base images and fails if the built PHP version differs from the current upstream image.
Immutable tags are never overwritten: when the name already exists on Docker Hub, `build.sh` adds `.2`, `.3`, ….

## Versions

* **PHP patch versions are not pinned:** a rebuild picks up the latest patch release of the PHP minor version set in `matrix.json`.
* **PECL extension versions are pinned** (`ARG`s in the `Dockerfile`, overridable per image in `matrix.json`).
  Do not unpin them: e.g. an unpinned decimal installs 2.x, which breaks the API used by existing apps.
* Downloads outside apt and PECL are checksum-verified (mpdecimal, wkhtmltopdf); keep it that way when bumping versions.

## Changes

`master` is the only branch. A ruleset protects it: changes go through pull requests, the `result` check must pass,
force pushes and deletion are blocked. Repository admins can bypass the ruleset, for emergencies only.

The old per-version branches and tags are preserved as `archive/branch/*` and `archive/tag/*` tags.

## CI

* `build.yml`: pull requests build and smoke-test the affected images; pushes to `master` also publish them.
  Manual runs take image ids (or `all`) and an optional push. Frozen legacy images are republished only when their own files change.
* `upstream-check.yml`: daily, rebuilds and publishes images whose official php base image has changed
  (compares the `org.opencontainers.image.base.digest` label set by `build.sh`).
* Requires the repository secret `DOCKERHUB_TOKEN` (Docker Hub access token, read & write) and the variable `DOCKERHUB_USERNAME`.

## Legacy images

* `legacy/php7.4-base` and `legacy/php5.6-base` are the official docker-library recipes, changed only where marked `maidea:`.
  `patches/` holds the security patches applied to the signature-verified PHP release tarballs:
  * 7.4: [php/php-src@712e60f9edfd](https://github.com/php/php-src/commit/712e60f9edfd) (PHP security team backport)
  * 5.6: patch 0261 of php5.6 5.6.40-104 from [packages.sury.org](https://packages.sury.org/php/) (Ondřej Surý's backport of the same fix)
* The bases are built locally first (`prebuild` in `matrix.json`) as `maidea-local/php:*` and are never pushed.
* 7.4 installs packages from `archive.debian.org` (Debian 11 is out of support).
* 5.6 can only be rebuilt until **2027-04-12**, when the Debian key that still verifies its package archive expires.
