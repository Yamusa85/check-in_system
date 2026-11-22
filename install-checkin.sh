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
FLASK_HOST="${FLASK_HOST:-127.0.0.1}"
FLASK_PORT="${FLASK_PORT:-5000}"

log()  { printf '\033[1;34m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- Pre-flight checks ----------
[[ $EUID -ne 0 ]] || die "Do not run this script as root. Run as your normal user; sudo will be invoked when needed."
command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v apt-get >/dev/null 2>&1 || die "This script targets Debian/Ubuntu (apt)."

# ---------- 1. Install system packages ----------
log "Updating apt package index..."
sudo apt-get update -y

# Map Python module -> apt package, with pip fallback names
declare -A APT_PKGS=(
  [sqlite3]="sqlite3"
  [flask]="python3-flask"
  [flask_login]="python3-flask-login"
  [werkzeug]="python3-werkzeug"
  [pandas]="python3-pandas"
  [openpyxl]="python3-openpyxl"
)

log "Installing system dependencies via apt..."
# Required base packages
sudo apt-get install -y --no-install-recommends \
  git curl ca-certificates \
  python3 python3-venv python3-pip \
  sqlite3 libsqlite3-dev \
  build-essential python3-dev

# Try each Flask/Pandas/OpenPyXL package; fall back to pip later if unavailable
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
  # Map module names to their pip distribution names
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
    # sqlite3 is stdlib; only fall back if truly missing
    if [[ "$mod" == "sqlite3" ]]; then
      python3 -c 'import sqlite3' 2>/dev/null || pip install "$name"
    else
      pip install "$name"
    fi
  done
fi

# ---------- 5. Optional: launch helper script ----------
RUNNER="$INSTALL_DIR/run.sh"
cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$INSTALL_DIR"
source "$VENV_DIR/bin/activate"
exec python3 app.py
EOF
chmod +x "$RUNNER"

# ---------- 6. Smoke test ----------
log "Performing import smoke test..."
"$VENV_DIR/bin/python" - <<'PY'
import flask, flask_login, werkzeug, pandas, openpyxl, sqlite3
print("imports OK:", flask.__version__, pandas.__version__, openpyxl.__version__)
PY

cat <<EOF

✅ Installation complete.

  App directory : $INSTALL_DIR
  Virtualenv    : $VENV_DIR
  Run with      : $RUNNER

To start the app manually:

  cd "$INSTALL_DIR"
  source .venv/bin/activate
  python3 app.py

If app.py uses Flask's dev server, it will be reachable at
  http://${FLASK_HOST}:${FLASK_PORT}/

Note: checkin.db and schema.sql initialization are handled by app.py
on first run — this script does not create the database.
EOF
