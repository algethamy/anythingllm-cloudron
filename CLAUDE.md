# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Cloudron package for upstream [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm). There is no application source here. The repo only contains the Dockerfile, the container entrypoint (`start.sh`), the Cloudron manifest, and the env template. Upstream code is downloaded at image-build time from the GitHub release tarball.

- App ID: `com.cloudron.anythingllm`
- Upstream version is pinned in **three places that must stay in sync**: `ARG ANYTHINGLLM_VERSION` (twice, in the `upstream-source` stage and the final stage of the Dockerfile), `ENV DEPLOYMENT_VERSION`, and `CURRENT_UPSTREAM_VERSION` in `start.sh`. Also update the `(AnythingLLM vX.Y.Z)` suffix in the manifest description and the README.
- Package version lives in `CloudronManifest.json` `version` and is tracked in `CHANGELOG.md` (format: `[x.y.z]` header followed by `* ` bullets). `CloudronVersions.json` is the published-versions registry and **must be updated by hand on every release**: add a `versions["x.y.z"]` entry whose `manifest` is a copy of `CloudronManifest.json` with `postInstallMessage` and `changelog` inlined as text (contents of `POSTINSTALL.md` and the new changelog block), plus a `dockerImage` field (`docker.io/algethamy/anythingllm-cloudron:x.y.z`), and `creationDate`/`ts` (RFC 1123 GMT) with `publishState: "published"`. Keep 4-space indentation and no trailing newline so the diff stays additive.

## Commands

There is no test suite, linter, or package.json. Development is the standard Cloudron packaging loop:

```bash
# Build the image (multi-arch aware; TARGETARCH selects Chromium strategy)
docker build -t <registry>/cloudron-anythingllm:<tag> .

# Install / update on a Cloudron instance
cloudron install --image <registry>/cloudron-anythingllm:<tag> -l <subdomain>
cloudron update  --image <registry>/cloudron-anythingllm:<tag> --app <subdomain>

# Debug a running instance
cloudron logs --app <subdomain> -f
cloudron exec --app <subdomain>

# Sanity-check the entrypoint locally
bash -n start.sh
```

## Architecture

### Dockerfile stages
1. `upstream-source` (debian) downloads and extracts the upstream tarball.
2. `frontend-build` (node:18, runs on `$BUILDPLATFORM`) does `yarn build` of the React frontend; output is copied into `/app/code/server/public`.
3. Final stage on `cloudron/base:5.0.0` installs Node 18 from NodeSource, `yarn@1.22.19`, `uv`, Chromium runtime libs, then copies `server/` and `collector/` and runs `yarn install --production` in each. On arm64 it downloads a prebuilt Chromium zip to `/app/chrome-linux` and sets `PUPPETEER_*` env instead of letting puppeteer download one.

### Read-only code vs. writable data
Cloudron mounts `/app/code` read-only and only `/app/data` (the `localstorage` addon) persists. Everything upstream expects to write is redirected via symlinks created at the end of the Dockerfile:

| Symlink in `/app/code`            | Target in `/app/data`          |
|-----------------------------------|--------------------------------|
| `server/.env`, `collector/.env`   | `server.env`                   |
| `server/storage`                  | `storage`                      |
| `collector/hotdir`                | `collector/hotdir`             |
| `collector/outputs`               | `collector/outputs`            |
| `collector/storage`               | `collector/storage`            |
| `server/node_modules`             | `server/node_modules`          |
| `collector/node_modules`          | `collector/node_modules`       |

`node_modules` are symlinked too because Prisma must write its generated client at runtime. The build-time copies are stashed in `/app/code/defaults/{server,collector}/node_modules` and `start.sh` copies them into `/app/data` on first start, or re-copies them when `/app/data/.upstream_version` differs from `CURRENT_UPSTREAM_VERSION`. The pristine upstream `server/storage` tree and `server.env.template` are also kept under `/app/code/defaults/` for seeding.

### start.sh flow (runs as root, then re-execs as `cloudron`)
1. `ensure_directories` creates the `/app/data` tree idempotently.
2. `initialize_config` seeds `server.env` from the template on first run, strips `UID=`/`GID=` lines (bash treats `UID` as readonly when the file is sourced), forces `SERVER_PORT`/`COLLECTOR_PORT`/`STORAGE_DIR`/`DISABLE_TELEMETRY`, and generates `JWT_SECRET`/`SIG_KEY`/`SIG_SALT` only when empty or still `__GENERATE__`. User-set values in `server.env` are otherwise preserved across restarts.
3. `sync_runtime_dependencies` performs the node_modules copy/refresh described above.
4. `finalize_permissions` chowns `/app/data`, then `drop_privileges_if_needed` re-execs the script via `gosu cloudron` with `--child`.
5. As `cloudron`: sources `server.env`, sets `HOME`/`TMPDIR` under `/app/data`, exports Chromium paths if the arm64 binary exists, runs `prisma generate` + `prisma migrate deploy`, writes `.initialized` and `.upstream_version`, then launches `server/index.js` and `collector/index.js` as background processes. `wait -n` exits the container if either dies so Cloudron restarts it.

### Runtime behavior notes
- The app starts in upstream's single-user mode (no login). Multi-user mode is a one-way switch enabled in the UI; see `POSTINSTALL.md`.
- Server listens on 3001 (Cloudron `httpPort`); collector on 8888 is internal only.
- `ANYTHING_LLM_RUNTIME=cloudron` is set as an image env var.
