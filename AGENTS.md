# AGENTS.md

## Purpose
Docker images (`maidea/webserver` on Docker Hub) that serve a PHP app mounted at `/src` with Apache + mod_php.
There is no app code in this repo. `README.md` is for image users (public, also shown on Docker Hub);
maintainer notes go in `MAINTAINING.md`. The images are offered as-is, best effort (`LICENSE`: all rights reserved).

## Layout
- `Dockerfile`: current PHP 8.x images (versions in `matrix.json`). Stages: `mpdecimal` (checksum-verified libmpdec build), `base`, `dev`, `prod` (default target).
  PHP extensions are installed with `install-php-extensions` (mlocati/docker-php-extension-installer, pinned).
- `config/php/*.ini`, `config/apache/*.conf`: copied into the 8.x images; `common.ini` is shared, the rest is per target.
- `shared/`: used by all images (entrypoint, health check, reverse-proxy config); the legacy Dockerfiles get it as the `shared` build context from `build.sh`.
- `legacy/php<version>/`: end-of-life PHP versions for internal projects: Debian 12 + PHP from Sury's packages (security backports),
  targets `prod`/`dev`. They must keep behaving like the earlier images (extensions in `extensions.txt`/`modules.txt`,
  checked at build time). Change only to keep them building, secure or compatible.
- `matrix.json`: single source of truth for every published image (context, target, build args, tags, smoke-test kind).
- `scripts/build.sh`: builds from `matrix.json` (`--smoke`, `--push`). `tests/smoke.sh`: checks a built image through a running container.
- `scripts/changed-images.sh`: decides which images CI builds and publishes for a change; `scripts/outdated-images.sh`: which ones the daily check rebuilds.

## Workflows
```sh
scripts/build.sh --smoke prod-8.4                  # build + smoke test one image, no push
scripts/build.sh --smoke                           # all images
scripts/changed-images.sh origin/master --publish  # images a push to master would publish
```
Build for `linux/amd64` only (wkhtmltopdf is an amd64 .deb). Do not add `--platform` to `FROM` lines.

## Publishing
- A push to `master` is a release: CI builds, smoke-tests and publishes every affected image to Docker Hub.
  Confirm with the user before pushing; check what will be published with `scripts/changed-images.sh` first. Docs-only changes publish nothing.
- The Docker Hub overview is a copy of `README.md` and is not synced automatically: after changing the README,
  prepare the overview for the user to paste (relative and in-page links rewritten, since they do not work on Docker Hub).
- After a publish, verify the result: pull the published tag and run `tests/smoke.sh` against it.

## Rules
- Keep PECL extension versions pinned (decimal 2.x breaks the API used by apps). PHP patch versions float on purpose.
- Downloads outside apt/PECL are checksum-verified (mpdecimal, wkhtmltopdf); keep it that way when bumping versions.
- Extensions are the same in every image, except where a PHP version cannot have one. Adding one: add it to the
  `install-php-extensions` list (8.x) and to `extensions.txt`/`modules.txt` (legacy), then to the list in `tests/smoke.sh`.
- New image or tag: add it to `matrix.json`; tags are never renamed or removed, since consumers pull them.
- Prod hardening must stay: `expose_php=Off`, `register_argc_argv=Off`, Apache `ServerTokens Prod`, loopback-only health check on `127.0.0.1:8081`.
- Changing any behaviour a user can see (ini values, env vars, included tools): update `README.md` in the same change.
- Verify changes with `scripts/build.sh --smoke <id>` before pushing images.
- Scripts must run on macOS's bash 3.2 as well as on Linux in CI: no `mapfile`, no GNU-only flags.
- New scripts must be committed as executable: check `git ls-files -s` shows mode `100755`
  (with `core.fileMode=false` a plain `chmod` is not recorded; use `git update-index --chmod=+x`).
- Local images can be stale: pull before inspecting or comparing an image (`docker pull`, or `--pull` on build/run).
