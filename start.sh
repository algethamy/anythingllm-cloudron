#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/app/code"
DATA_DIR="/app/data"
RUN_DIR="/run/anythingllm"
ENV_FILE="${DATA_DIR}/server.env"
ENV_TEMPLATE="${APP_DIR}/defaults/server.env"
STORAGE_TEMPLATE_DIR="${APP_DIR}/defaults/storage"
INIT_FLAG="${DATA_DIR}/.initialized"
VERSION_FILE="${DATA_DIR}/.upstream_version"
CURRENT_UPSTREAM_VERSION="1.17.0"

generate_secret() {
  local length="${1}"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}"
}

set_env_value() {
  local key="${1}"
  local value="${2}"
  local file="${3}"

  if grep -qE "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

ensure_secret_value() {
  local key="${1}"
  local length="${2}"
  local current_value

  current_value="$(sed -n "s/^${key}=//p" "${ENV_FILE}" | tail -n 1 || true)"
  if [[ -z "${current_value}" || "${current_value}" == "__GENERATE__" ]]; then
    set_env_value "${key}" "$(generate_secret "${length}")" "${ENV_FILE}"
  fi
}

ensure_directories() {
  mkdir -p \
    "${DATA_DIR}/storage/documents/custom-documents" \
    "${DATA_DIR}/storage/direct-uploads" \
    "${DATA_DIR}/storage/lancedb" \
    "${DATA_DIR}/storage/models" \
    "${DATA_DIR}/storage/tmp" \
    "${DATA_DIR}/collector/hotdir" \
    "${DATA_DIR}/collector/outputs" \
    "${DATA_DIR}/collector/storage/tmp" \
    "${DATA_DIR}/tmp" \
    "${RUN_DIR}"

  if [[ ! -f "${DATA_DIR}/collector/hotdir/__HOTDIR__.md" ]]; then
    printf '# Drop files here to import them into AnythingLLM.\n' > "${DATA_DIR}/collector/hotdir/__HOTDIR__.md"
  fi

  if [[ ! -f "${DATA_DIR}/collector/storage/tmp/.placeholder" ]]; then
    : > "${DATA_DIR}/collector/storage/tmp/.placeholder"
  fi
}

should_refresh_runtime_dependencies() {
  if [[ ! -f "${VERSION_FILE}" ]]; then
    return 0
  fi

  [[ "$(cat "${VERSION_FILE}" 2>/dev/null || true)" != "${CURRENT_UPSTREAM_VERSION}" ]]
}

sync_runtime_tree() {
  local source_dir="${1}"
  local target_dir="${2}"
  local refresh="${3}"

  mkdir -p "$(dirname "${target_dir}")"

  if [[ "${refresh}" == "true" && -e "${target_dir}" ]]; then
    rm -rf "${target_dir}"
  fi

  if [[ ! -e "${target_dir}" ]]; then
    cp -a "${source_dir}" "${target_dir}"
  fi
}

initialize_config() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_TEMPLATE}" "${ENV_FILE}"
  fi

  # Bash reserves UID as a readonly shell variable, so strip docker-compose
  # ownership keys from persisted env files before sourcing them.
  sed -i '/^UID=/d;/^GID=/d' "${ENV_FILE}"

  if [[ -d "${STORAGE_TEMPLATE_DIR}" ]]; then
    cp -a --update=none "${STORAGE_TEMPLATE_DIR}/." "${DATA_DIR}/storage/"
  fi

  set_env_value "SERVER_PORT" "3001" "${ENV_FILE}"
  set_env_value "COLLECTOR_PORT" "8888" "${ENV_FILE}"
  set_env_value "STORAGE_DIR" "/app/data/storage" "${ENV_FILE}"
  set_env_value "DISABLE_TELEMETRY" "true" "${ENV_FILE}"

  ensure_secret_value "JWT_SECRET" "32"
  ensure_secret_value "SIG_KEY" "64"
  ensure_secret_value "SIG_SALT" "64"
}

sync_runtime_dependencies() {
  local refresh="false"

  if should_refresh_runtime_dependencies; then
    refresh="true"
  fi

  sync_runtime_tree "${APP_DIR}/defaults/server/node_modules" "${DATA_DIR}/server/node_modules" "${refresh}"
  sync_runtime_tree "${APP_DIR}/defaults/collector/node_modules" "${DATA_DIR}/collector/node_modules" "${refresh}"
}

finalize_permissions() {
  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R cloudron:cloudron "${DATA_DIR}" "${RUN_DIR}"
  fi
}

drop_privileges_if_needed() {
  if [[ "${1:-}" != "--child" && "$(id -u)" -eq 0 ]]; then
    exec gosu cloudron:cloudron "$0" --child
  fi
}

load_runtime_env() {
  set -a
  . "${ENV_FILE}"
  set +a

  export HOME="${DATA_DIR}"
  export TMPDIR="${DATA_DIR}/tmp"

  if [[ -x "/app/chrome-linux/chrome" ]]; then
    export CHROME_PATH="/app/chrome-linux/chrome"
    export PUPPETEER_EXECUTABLE_PATH="/app/chrome-linux/chrome"
    export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD="true"
  fi
}

run_prisma_migrations() {
  cd "${APP_DIR}/server"
  npx prisma generate --schema=./prisma/schema.prisma
  npx prisma migrate deploy --schema=./prisma/schema.prisma
}

launch_services() {
  local server_pid collector_pid exit_code

  (
    cd "${APP_DIR}/server"
    exec node index.js
  ) &
  server_pid=$!

  (
    cd "${APP_DIR}/collector"
    exec node index.js
  ) &
  collector_pid=$!

  trap 'kill "${server_pid}" "${collector_pid}" 2>/dev/null || true' INT TERM

  set +e
  wait -n "${server_pid}" "${collector_pid}"
  exit_code=$?
  set -e

  kill "${server_pid}" "${collector_pid}" 2>/dev/null || true
  wait "${server_pid}" "${collector_pid}" 2>/dev/null || true
  exit "${exit_code}"
}

main() {
  ensure_directories
  initialize_config
  sync_runtime_dependencies
  finalize_permissions
  drop_privileges_if_needed "${1:-}"

  load_runtime_env
  run_prisma_migrations

  touch "${INIT_FLAG}"
  printf '%s\n' "${CURRENT_UPSTREAM_VERSION}" > "${VERSION_FILE}"

  launch_services
}

main "$@"
