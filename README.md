AnythingLLM for Cloudron
========================

This repository packages upstream [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm) `v1.17.0` for Cloudron using a fresh packaging layout.

Overview
--------
- App ID: `com.cloudron.anythingllm`
- Upstream version: `v1.17.0`
- Runtime base image: `cloudron/base:5.0.0`
- HTTP port: `3001`
- Persistent addon: `localstorage`

Package Layout
--------------
- `/app/code` contains the read-only application code copied from the upstream `v1.17.0` release tarball.
- `/app/data` contains all writable state and configuration required by Cloudron.
- Dockerfile-created symlinks redirect the upstream writable paths into `/app/data`:
  - `/app/code/server/.env` -> `/app/data/server.env`
  - `/app/code/server/storage` -> `/app/data/storage`
  - `/app/code/collector/hotdir` -> `/app/data/collector/hotdir`
  - `/app/code/collector/outputs` -> `/app/data/collector/outputs`
  - `/app/code/collector/storage` -> `/app/data/collector/storage`

Startup Flow
------------
- `start.sh` creates the required `/app/data` directory structure idempotently.
- On first run, `start.sh` copies the scaffolded `server.env` template into `/app/data/server.env`.
- Required secrets are generated only when placeholders are still present.
- Prisma migrations run before the services are launched.
- The script then starts the upstream server and collector processes directly.

Notes
-----
- This package keeps upstream runtime behavior intact wherever possible and only adapts filesystem and startup concerns for Cloudron.
- Browser-based scraping features still depend on Chromium support inside the container environment.
- The package is ready for the normal project build workflow when repository changes are complete.
