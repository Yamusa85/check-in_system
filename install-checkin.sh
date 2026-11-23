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

# ---------- 2a. Locate the real app root ----------
# The repo may either keep app.py at the top level, or nest it inside a
# subdirectory with the same name (e.g. INSTALL_DIR/checkin-system/app.py).
if [[ -f "$INSTALL_DIR/app.py" ]]; then
  APP_ROOT="$INSTALL_DIR"
elif [[ -f "$INSTALL_DIR/checkin-system/app.py" ]]; then
  APP_ROOT="$INSTALL_DIR/checkin-system"
  log "Detected nested layout — app root is: $APP_ROOT"
else
  die "Could not locate app.py under '$INSTALL_DIR' or '$INSTALL_DIR/checkin-system'."
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
  "templates/seating_map.html"
)
missing=()
for f in "${REQUIRED_FILES[@]}"; do
  [[ -f "$APP_ROOT/$f" ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  die "Missing expected files under '$APP_ROOT': ${missing[*]}"
fi
log "All expected application files present in $APP_ROOT."

# ---------- 4. Python virtualenv + deps ----------
VENV_DIR="$INSTALL_DIR/.venv"

# Rebuild the venv if missing or broken (broken bin/python symlink,
# or the interpreter it points at no longer exists).
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  log "Creating Python virtualenv at $VENV_DIR"
  "$PYTHON_BIN" -m venv --clear "$VENV_DIR"
fi

# Sanity: the venv's python must be executable and must report a real path
VENV_PY="$VENV_DIR/bin/python"
[[ -x "$VENV_PY" ]] || die "Venv python missing or not executable: $VENV_PY"

# Make sure pip exists in the venv and is the venv's own pip.
# Use `python -m pip` (not the `pip` shim) so we can never accidentally
# hit the system pip or ~/.local/bin/pip.
if ! "$VENV_PY" -m pip --version >/dev/null 2>&1; then
  log "Bootstrapping pip inside venv..."
  "$VENV_PY" -m ensurepip --upgrade
fi

log "Upgrading pip/wheel in venv..."
"$VENV_PY" -m pip install --upgrade pip wheel setuptools >/dev/null

# Install all Python deps into the venv, regardless of what apt provided.
# (apt may have installed system copies; venv-local copies take precedence
# for the service and for the smoke test.)
log "Installing Python dependencies into venv..."
PIP_PKGS=(Flask Flask-Login Werkzeug pandas openpyxl)

# If sqlite3 stdlib is missing (very rare), add a pip fallback for it.
if ! "$VENV_PY" -c 'import sqlite3' >/dev/null 2>&1; then
  warn "sqlite3 stdlib module not importable — adding pysqlite3-binary fallback"
  PIP_PKGS+=(pysqlite3-binary)
fi

"$VENV_PY" -m pip install --no-input --upgrade "${PIP_PKGS[@]}"

# ---------- 5. Smoke test ----------
log "Performing smoke test with venv interpreter..."
( cd "$APP_ROOT" && "$VENV_PY" -I - <<'PY'
import os, sys
print("interpreter:", sys.executable)
print("cwd        :", os.getcwd())
import flask, flask_login, werkzeug, pandas, openpyxl, sqlite3
print("flask      :", flask.__version__, "from", flask.__file__)
print("pandas     :", pandas.__version__)
print("openpyxl   :", openpyxl.__version__)
PY
) || die "Smoke test failed — see the traceback above."

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
WorkingDirectory=${APP_ROOT}
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONNOUSERSITE=1
Environment=FLASK_HOST=${FLASK_HOST}
Environment=FLASK_PORT=${FLASK_PORT}
# app.py already initializes schema.sql / checkin.db itself on startup.
ExecStart=${VENV_DIR}/bin/python ${APP_ROOT}/app.py
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

log "Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"
sudo systemctl restart "${SERVICE_NAME}.service"

sleep 2
if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  log "Service is running."
else
  warn "Service failed to start. Inspect logs with:"
  warn "  sudo journalctl -u ${SERVICE_NAME}.service -n 50 --no-pager"
fi

cat <<EOF

✅ Installation complete.

  Install dir   : $INSTALL_DIR
  App root      : $APP_ROOT
  Virtualenv    : $VENV_DIR
  Service unit  : $SERVICE_FILE
  Service name  : ${SERVICE_NAME}

Service management:

  sudo systemctl status ${SERVICE_NAME}
  sudo systemctl restart ${SERVICE_NAME}
  sudo systemctl stop ${SERVICE_NAME}
  sudo journalctl -u ${SERVICE_NAME} -f        # live logs

Checkin database (checkin.db) and schema.sql are initialized by app.py
on first run — this script does not create the database.

App reachable at: http://${FLASK_HOST}:${FLASK_PORT}/
EOF
