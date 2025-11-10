#!/usr/bin/env bash

# Entry point for the modularized Xray install toolkit.
# Each logical section of the legacy script now lives under modules/*.sh
# so that every area can be maintained independently.
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/modules"

MODULES=(
  "01_bootstrap.sh"
  "02_preflight.sh"
  "03_nginx.sh"
  "04_tls.sh"
  "05_core_runtime.sh"
  "06_client_config.sh"
  "07_services.sh"
  "08_ops_tools.sh"
  "09_routing.sh"
  "10_install_manage.sh"
  "11_menu.sh"
)

for module in "${MODULES[@]}"; do
  module_path="${MODULE_DIR}/${module}"
  if [[ ! -f "${module_path}" ]]; then
    echo "[FATAL] Missing module: ${module_path}" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${module_path}"
done

# 保持原有脚本的启动顺序
cronFunction
menu
