#!/usr/bin/env bash
# install-checkin.sh
# Usage:
#   ./install-checkin.sh                          # default repo + target
#   REPO_URL=https://github.com/Yamusa85/check-in_system.git ./install-checkin.sh
#   INSTALL_DIR=/opt/checkin-system ./install-checkin.sh
#
# Must be run as a normal user (it will call sudo when needed).

set -euo pipefail

# ---------- Configuration (override via env vars) ----------
REPO_URL="${REPO_URL:-https://github.com/Yamusa85/check-in_system.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/checkin-system}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SERVICE_NAME="${SERVICE_NAME:-checkin-system}"
FLASK_HOST="${FLASK_HOST:-127.0.0.1}"
FLASK_PORT="${FLASK_PORT:-5000}"

log()  { printf '\033[1;34m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- Pre-flight checks ----------
[[ $EUID -ne 0 ]] || die "Do not run this script as root. Run as your normal user; sudo will be invoked when needed."
command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v apt-get >/dev/null 2>&1 || die "This script targets Debian/Ubuntu (apt)."

# Capture the invoking user for the systemd unit
RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"

# ---------- 1. Install system packages ----------
log "Updating apt package index..."
sudo apt-get update -y

declare -A APT_PKGS=(
  [sqlite3]="sqlite3"
  [flask]="python3-flask"
  [flask_login]="python3-flask-login"
  [werkzeug]="python3-werkzeug"
  [pandas]="python3-pandas"
  [openpyxl]="python3-openpyxl"
)

log "Installing system dependencies via apt..."
sudo apt-get install -y --no-install-recommends \
  git curl ca-certificates \
  python3 python3-venv python3-pip \
  sqlite3 libsqlite3-dev \
  build-essential python3-dev

PIP_FALLBACK=()
for mod in "${!APT_PKGS[@]}"; do
  pkg="${APT_PKGS[$mod]}"
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    log "Installing apt package: $pkg"
    sudo apt-get install -y --no-install-recommends "$pkg" || PIP_FALLBACK+=("$mod")
  else
    warn "apt package '$pkg' not found; will install via pip: $mod"
    PIP_FALLBACK+=("$mod")
  fi
done

# ---------- 2. Fetch the application ----------
log "Fetching application into: $INSTALL_DIR"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "Existing git checkout found — pulling latest..."
  git -C "$INSTALL_DIR" fetch --all --prune
  git -C "$INSTALL_DIR" reset --hard origin/HEAD
elif [[ -d "$INSTALL_DIR" ]] && [[ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
  die "Directory '$INSTALL_DIR' exists and is not empty (and not a git repo). Move it aside or set INSTALL_DIR to another path."
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# ---------- 3. Verify required files are present ----------
REQUIRED_FILES=(
  "app.py"
  "schema.sql"
  "templates/admin_dashboard.html"
  "templates/base.html"
  "templates/create_event.html"
  "templates/edit_event.html"
  "templates/event_select.html"
  "templates/guest_search.html"
  "templates/login.html"
)
missing=()
for f in "${REQUIRED_FILES[@]}"; do
  [[ -f "$INSTALL_DIR/$f" ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  die "Missing expected files in '$INSTALL_DIR': ${missing[*]}"
fi
log "All expected application files present."

# ---------- 4. Python virtualenv + pip fallbacks ----------
VENV_DIR="$INSTALL_DIR/.venv"
if [[ ! -d "$VENV_DIR" ]]; then
  log "Creating Python virtualenv at $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip wheel >/dev/null

if (( ${#PIP_FALLBACK[@]} > 0 )); then
  log "Installing pip fallbacks: ${PIP_FALLBACK[*]}"
  declare -A PIP_NAMES=(
    [flask]="Flask"
    [flask_login]="Flask-Login"
    [werkzeug]="Werkzeug"
    [pandas]="pandas"
    [openpyxl]="openpyxl"
    [sqlite3]="pysqlite3-binary"
  )
  for mod in "${PIP_FALLBACK[@]}"; do
    name="${PIP_NAMES[$mod]:-$mod}"
    if [[ "$mod" == "sqlite3" ]]; then
      python3 -c 'import sqlite3' 2>/dev/null || pip install "$name"
    else
      pip install "$name"
    fi
  done
fi

# ---------- 5. Smoke test ----------
log "Performing import smoke test..."
"$VENV_DIR/bin/python" - <<'PY'
import flask, flask_login, werkzeug, pandas, openpyxl, sqlite3
print("imports OK:", flask.__version__, pandas.__version__, openpyxl.__version__)
PY

# ---------- 6. Install systemd service ----------
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
log "Installing systemd unit: $SERVICE_FILE"

sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Check-in System (Flask)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${INSTALL_DIR}
Environment=PYTHONUNBUFFERED=1
Environment=FLASK_HOST=${FLASK_HOST}
Environment=FLASK_PORT=${FLASK_PORT}
# app.py already initializes schema.sql / checkin.db itself on startup.
ExecStart=${VENV_DIR}/bin/python ${INSTALL_DIR}/app.py
Restart=on-failure
RestartSec=5

# Basic hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

log "Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"
sudo systemctl restart "${SERVICE_NAME}.service"

# Give it a moment, then report status
sleep 2
if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  log "Service is running."
else
  warn "Service failed to start. Inspect logs with:"
  warn "  sudo journalctl -u ${SERVICE_NAME}.service -n 50 --no-pager"
fi

cat <<EOF

✅ Installation complete.

  App directory : $INSTALL_DIR
  Virtualenv    : $VENV_DIR
  Service unit  : $SERVICE_FILE
  Service name  : ${SERVICE_NAME}

Service management:

  sudo systemctl status ${SERVICE_NAME}
  sudo systemctl restart ${SERVICE_NAME}
  sudo systemctl stop ${SERVICE_NAME}
  sudo journalctl -u ${SERVICE_NAME} -f        # live logs

The service starts automatically on boot (WantedBy=multi-user.target)
and restarts on failure (Restart=on-failure).

Checkin database (checkin.db) and schema.sql are initialized by app.py
on first run — this script does not create the database.

App reachable at: http://${FLASK_HOST}:${FLASK_PORT}/
EOF
