#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="tempest-ecobee-humidity"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/${SERVICE_NAME}"
CONFIG_DIR="/etc/${SERVICE_NAME}"
STATE_DIR="/var/lib/${SERVICE_NAME}"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_PATH="/etc/systemd/system/${SERVICE_NAME}.timer"

if [[ $(id -u) -ne 0 ]]; then
  echo "This installer must be run as root (try sudo)."
  exit 1
fi

mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}" "${STATE_DIR}"

# Copy application code
install -m 755 "${SCRIPT_DIR}/set_humidity.rb" "${INSTALL_DIR}/set_humidity.rb"
if [[ -f "${SCRIPT_DIR}/config.example.yml" ]]; then
  install -m 644 "${SCRIPT_DIR}/config.example.yml" "${INSTALL_DIR}/config.example.yml"
fi

# Copy configuration if present next to installer
if [[ -f "${SCRIPT_DIR}/config.yml" ]]; then
  install -m 600 "${SCRIPT_DIR}/config.yml" "${CONFIG_DIR}/config.yml"
elif [[ ! -f "${CONFIG_DIR}/config.yml" && -f "${SCRIPT_DIR}/config.example.yml" ]]; then
  install -m 600 "${SCRIPT_DIR}/config.example.yml" "${CONFIG_DIR}/config.yml"
  echo "Copied config.example.yml to ${CONFIG_DIR}/config.yml. Update it with your credentials."
fi

# Install systemd units
install -m 644 "${SCRIPT_DIR}/systemd/${SERVICE_NAME}.service" "${SERVICE_PATH}"
install -m 644 "${SCRIPT_DIR}/systemd/${SERVICE_NAME}.timer" "${TIMER_PATH}"

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"

# Optional: run immediately once during install
systemctl start "${SERVICE_NAME}.service"

cat <<EOF
Installation complete.
Configuration: ${CONFIG_DIR}/config.yml
State files: ${STATE_DIR}
Service unit: ${SERVICE_PATH}
Timer unit: ${TIMER_PATH}
Use 'systemctl status ${SERVICE_NAME}.service' to view the last run.
EOF
