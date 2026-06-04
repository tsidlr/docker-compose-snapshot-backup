#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  snapshot.sh
#  Exports all images and volumes of the
#  docker-compose.yml in the current directory
#  + the complete repo into a tar.
#
#  Usage:
#    ./snapshot.sh
# ─────────────────────────────────────────────

# ── Find Compose File ─────────────────────────
if [ -f "docker-compose.yml" ]; then
  COMPOSE_FILE="docker-compose.yml"
elif [ -f "docker-compose.yaml" ]; then
  COMPOSE_FILE="docker-compose.yaml"
else
  echo "❌ No docker-compose.yml or docker-compose.yaml found."
  echo "   Please open the terminal in the correct project folder."
  exit 1
fi

# ── Checks ────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "❌ Docker not found. Please install Docker Desktop."
  exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PROJECT_NAME=$(basename "$PWD")
WORK_DIR="${SNAPSHOT_TMPDIR:-/tmp}"
SNAPSHOT_DIR="${WORK_DIR}/snapshot_${PROJECT_NAME}_${TIMESTAMP}"
FINAL_TAR="$(pwd)/snapshot_${PROJECT_NAME}_${TIMESTAMP}.tar"

echo ""
echo "📦 snapshot.sh"
echo "   Project : $PROJECT_NAME"
echo "   Compose : $COMPOSE_FILE"
echo "   Output  : $(basename "$FINAL_TAR")"
echo "─────────────────────────────────────────"

# ── Check available disk space ────────────────
IMAGE_LIST=$(docker compose config --images 2>/dev/null | sort -u)

if [ -z "$IMAGE_LIST" ]; then
  echo "❌ No images found. Are the containers built?"
  echo "   Try first: docker compose build"
  exit 1
fi

TOTAL_IMAGE_BYTES=0
while IFS= read -r img; do
  SIZE=$(docker inspect --format='{{.Size}}' "$img" 2>/dev/null || echo 0)
  TOTAL_IMAGE_BYTES=$((TOTAL_IMAGE_BYTES + SIZE))
done <<< "$IMAGE_LIST"

REPO_KB=$(du -sk "$(pwd)" 2>/dev/null | cut -f1)
NEEDED_BYTES=$(( (TOTAL_IMAGE_BYTES + REPO_KB * 1024) * 12 / 10 ))
AVAIL_KB=$(df -k "$WORK_DIR" 2>/dev/null | awk 'NR==2{print $4}')
AVAIL_BYTES=$((AVAIL_KB * 1024))

if [ "$AVAIL_BYTES" -lt "$NEEDED_BYTES" ]; then
  AVAIL_HR=$(awk "BEGIN{printf \"%.1f GB\", $AVAIL_BYTES/1073741824}")
  NEEDED_HR=$(awk "BEGIN{printf \"%.1f GB\", $NEEDED_BYTES/1073741824}")
  echo ""
  echo "❌ Not enough free space in $WORK_DIR"
  echo "   Available : $AVAIL_HR"
  echo "   Estimated : $NEEDED_HR"
  echo ""
  echo "   Use a different staging directory:"
  echo "   SNAPSHOT_TMPDIR=/mnt/data ../snapshot.sh"
  exit 1
fi

mkdir -p "$SNAPSHOT_DIR/volumes"

# ── Copy repo ─────────────────────────────────
echo ""
echo "📂 Copying repo..."
cp -r "$(pwd)/." "$SNAPSHOT_DIR/repo/"
echo "✅ Repo copied"

# ── Detect active dist/ bind-mounts and include them ─────────────────────────
echo ""
echo "🔍 Scanning for active dist/ bind-mounts..."

# Active (non-commented) volume lines with filesystem paths (., .., /, ~) containing dist/
while IFS= read -r line; do
  # Extract source path (everything before first :)
  BIND_SRC=$(echo "$line" | sed -E 's/^\s+-\s+([^:]+):.*/\1/' | tr -d ' ')

  # Resolve absolute path
  ABS_PATH=$(cd "$(pwd)" && realpath "$BIND_SRC" 2>/dev/null || true)

  if [ -z "$ABS_PATH" ] || [ ! -d "$ABS_PATH" ]; then
    echo "   ⚠️  Folder not found: $BIND_SRC — skipping."
    continue
  fi

  # Build relative target path in snapshot
  # Take absolute path and derive a clean relative name from it
  # e.g. /home/user/worktrees/27271/mapping-frontend/dist/... -> mapping-frontend/dist/...
  # Take the last part starting from the folder that contains dist/
  DIST_RELATIVE=$(echo "$ABS_PATH" | sed 's|.*/\([^/]*/dist/\)|\1|')
  DEST_PATH="$SNAPSHOT_DIR/repo/dist/$DIST_RELATIVE"
  mkdir -p "$(dirname "$DEST_PATH")"
  cp -r "$ABS_PATH" "$(dirname "$DEST_PATH")"

  # Patch docker-compose.yaml: old path -> new relative path
  NEW_PATH="./dist/$DIST_RELATIVE"
  sed -i "s|${BIND_SRC}|${NEW_PATH}|g" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"

  echo "   ✅ $BIND_SRC → $NEW_PATH"
done < <(grep -E "^\s+-\s+[./~]" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE" | grep "dist")
echo "✅ Bind-mounts checked"

# ── Generate restore scripts ──────────────────
echo ""
echo "📝 Generating restore scripts..."

# Generate restore.bat
cat > "$SNAPSHOT_DIR/start.bat" << 'BATEOF'
@echo off
echo.
echo  =========================================
echo   Start Environment - Docker Snapshot
echo  =========================================
echo.

REM Check if Docker is installed
where docker >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo  Docker is not installed!
    echo.
    echo  Please download and install Docker Desktop:
    echo  https://www.docker.com/products/docker-desktop
    echo.
    pause
    exit /b 1
)

REM Check if Docker is running
docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo  Docker is installed but not running!
    echo.
    echo  Please start Docker Desktop and wait until
    echo  the Docker icon appears in the taskbar.
    echo  Then run this file again.
    echo.
    pause
    exit /b 1
)

echo  Docker is running. Starting restore...
echo.
set SNAP_DIR=%~dp0
if "%SNAP_DIR:~-1%"=="\" set SNAP_DIR=%SNAP_DIR:~0,-1%
powershell -ExecutionPolicy Bypass -File "%SNAP_DIR%\restore.ps1" "%SNAP_DIR%"
pause
BATEOF

# Generate restore.ps1 (via printf to avoid Bash parsing of PS1 special characters)
printf '%s\n' \
'param(' \
'    [Parameter(Mandatory=$true, Position=0)]' \
'    [string]$SnapshotPath' \
')' \
'' \
'$ErrorActionPreference = "Stop"' \
'' \
'function Write-Step { param($msg) Write-Host $msg -ForegroundColor Cyan }' \
'function Write-Ok   { param($msg) Write-Host $msg -ForegroundColor Green }' \
'function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }' \
'function Write-Fail { param($msg) Write-Host $msg -ForegroundColor Red }' \
'' \
'$SnapshotPath = $SnapshotPath.TrimEnd("\").TrimEnd("/")' \
'' \
'Write-Host ""' \
'Write-Host "Restoring environment" -ForegroundColor White' \
'Write-Host "-----------------------------------------"' \
'' \
'if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {' \
'    Write-Fail "Docker is not installed."' \
'    Write-Host "   Please install Docker Desktop: https://www.docker.com/products/docker-desktop"' \
'    Read-Host "Press Enter to exit"' \
'    exit 1' \
'}' \
'' \
'# Path conversion Windows -> Docker (C:\Users\... -> /c/Users/...)' \
'function Convert-ToDockerPath {' \
'    param([string]$WinPath)' \
'    $p = $WinPath.Replace("\", "/")' \
'    if ($p -match "^([A-Za-z]):(.*)") { $p = "/" + $Matches[1].ToLower() + $Matches[2] }' \
'    return $p' \
'}' \
'' \
'# Load images' \
'Write-Host ""' \
'Write-Step "Loading images... (this may take a few minutes)"' \
'$ImagesFile = Join-Path $SnapshotPath "images.tar"' \
'if (-not (Test-Path $ImagesFile)) {' \
'    Write-Fail "images.tar not found in: $SnapshotPath"' \
'    Read-Host "Press Enter to exit"' \
'    exit 1' \
'}' \
'docker load -i $ImagesFile' \
'Write-Ok "Images loaded"' \
'' \
'# Restore volumes' \
'$VolumesPath = Join-Path $SnapshotPath "volumes"' \
'$RepoPath = Join-Path $SnapshotPath "repo"' \
'$ComposePath = Join-Path $RepoPath "docker-compose.yml"' \
'if (-not (Test-Path $ComposePath)) { $ComposePath = Join-Path $RepoPath "docker-compose.yaml" }' \
'' \
'if ((Test-Path $VolumesPath) -and (Get-ChildItem $VolumesPath -Filter "*.tar.gz" -ErrorAction SilentlyContinue)) {' \
'    Write-Host ""' \
'    Write-Step "Restoring volumes..."' \
'    $DockerVolumesPath = Convert-ToDockerPath $VolumesPath' \
'    $ComposeContent = Get-Content $ComposePath -Raw' \
'    Get-ChildItem $VolumesPath -Filter "*.tar.gz" | ForEach-Object {' \
'        $VolName = $_.BaseName -replace "\.tar$", ""' \
'        if ($ComposeContent -match "(?ms)^\s+${VolName}:.*?name:\s*(\S+)") {' \
'            $FullVolName = $Matches[1]' \
'            Write-Host "   o $VolName -> $FullVolName"' \
'            docker volume create $FullVolName | Out-Null' \
'            $result = docker run --rm -v "${FullVolName}:/volume_data" -v "${DockerVolumesPath}:/backup" alpine sh -c "rm -rf /volume_data/* /volume_data/.[!.]* 2>/dev/null; tar xzf /backup/${VolName}.tar.gz -C /volume_data" 2>&1' \
'            if ($LASTEXITCODE -eq 0) {' \
'                Write-Ok "     Done"' \
'            } else {' \
'                Write-Warn "     Error filling volume: $result"' \
'            }' \
'        } else {' \
'            Write-Warn "Volume $VolName not found in compose - skipping."' \
'        }' \
'    }' \
'    Write-Ok "Volumes restored"' \
'} else {' \
'    Write-Warn "No volumes in snapshot."' \
'}' \
'' \
'# Start containers — project name already set in docker-compose' \
'Write-Host ""' \
'Write-Step "Starting containers..."' \
'Set-Location $RepoPath' \
'docker compose up -d' \
'Write-Host ""' \
'Write-Host "-----------------------------------------"' \
'Write-Ok "Done! All containers are running."' \
'Write-Host ""' \
'docker compose ps 2>$null' \
'Write-Host ""' \
'Write-Host "   To stop: docker compose down"' \
'Write-Host "-----------------------------------------"' \
> "$SNAPSHOT_DIR/restore.ps1"

# Generate restore.sh (Linux / macOS)
cat > "$SNAPSHOT_DIR/restore.sh" << 'RESTOREEOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "${CYAN}$*${NC}"; }
ok()   { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
fail() { echo -e "${RED}$*${NC}"; }

echo ""
echo "Restoring environment"
echo "-----------------------------------------"

if ! command -v docker &>/dev/null; then
  fail "Docker is not installed."
  echo "   Please install Docker: https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker info &>/dev/null; then
  fail "Docker is installed but not running."
  echo "   Please start Docker and try again."
  exit 1
fi

echo ""
step "Loading images... (this may take a few minutes)"
IMAGES_FILE="$SCRIPT_DIR/images.tar"
if [ ! -f "$IMAGES_FILE" ]; then
  fail "images.tar not found in: $SCRIPT_DIR"
  exit 1
fi
docker load -i "$IMAGES_FILE"
ok "Images loaded"

VOLUMES_PATH="$SCRIPT_DIR/volumes"
REPO_PATH="$SCRIPT_DIR/repo"
COMPOSE_PATH="$REPO_PATH/docker-compose.yml"
[ ! -f "$COMPOSE_PATH" ] && COMPOSE_PATH="$REPO_PATH/docker-compose.yaml"

if [ -d "$VOLUMES_PATH" ] && ls "$VOLUMES_PATH"/*.tar.gz &>/dev/null; then
  echo ""
  step "Restoring volumes..."
  COMPOSE_CONTENT=$(cat "$COMPOSE_PATH")
  for vol_archive in "$VOLUMES_PATH"/*.tar.gz; do
    VOL_KEY=$(basename "$vol_archive" .tar.gz)
    FULL_VOL_NAME=$(echo "$COMPOSE_CONTENT" | awk "
      /^volumes:/ { in_vol=1 }
      in_vol && /^  ${VOL_KEY}:/ { found=1 }
      found && /name:/ { match(\$0, /name:[[:space:]]+([^[:space:]]+)/, a); print a[1]; exit }
    ")
    if [ -n "$FULL_VOL_NAME" ]; then
      echo "   o $VOL_KEY -> $FULL_VOL_NAME"
      docker volume create "$FULL_VOL_NAME" > /dev/null
      if docker run --rm \
        -v "${FULL_VOL_NAME}:/volume_data" \
        -v "${VOLUMES_PATH}:/backup" \
        alpine sh -c "rm -rf /volume_data/* /volume_data/.[!.]* 2>/dev/null; tar xzf /backup/${VOL_KEY}.tar.gz -C /volume_data"; then
        ok "     Done"
      else
        warn "     Error filling volume"
      fi
    else
      warn "   Volume $VOL_KEY not found in compose — skipping."
    fi
  done
  ok "Volumes restored"
else
  warn "No volumes in snapshot."
fi

echo ""
step "Starting containers..."
cd "$REPO_PATH"
docker compose up -d
echo ""
echo "-----------------------------------------"
ok "Done! All containers are running."
echo ""
docker compose ps 2>/dev/null || true
echo ""
echo "   To stop: docker compose down"
echo "-----------------------------------------"
RESTOREEOF
chmod +x "$SNAPSHOT_DIR/restore.sh"

echo "✅ start.bat, restore.ps1 and restore.sh generated"

# ── Generate snapshot-info.txt ────────────────
cat > "$SNAPSHOT_DIR/snapshot-info.txt" << INFOEOF
Snapshot:  ${PROJECT_NAME}_${TIMESTAMP}
Created:   $(date +"%Y-%m-%d %H:%M:%S")
Project:   $PROJECT_NAME
INFOEOF
echo "✅ snapshot-info.txt created"

# ── Export images ─────────────────────────────
echo ""
echo "🔍 Reading images from $COMPOSE_FILE..."
echo "   Found images:"
echo "$IMAGE_LIST" | while read -r img; do
  echo "   • $img"
done

echo ""
echo "💾 Exporting images... (this may take a few minutes)"

SNAPSHOT_TAG="${PROJECT_NAME}_${TIMESTAMP}"
TAGGED_IMAGE_LIST="/tmp/tagged_images_${TIMESTAMP}.txt"
> "$TAGGED_IMAGE_LIST"

while IFS= read -r img; do
  BASE=$(echo "$img" | sed 's/:[^:]*$//')
  NEW_TAG="${BASE}:${SNAPSHOT_TAG}"

  docker tag "$img" "$NEW_TAG"
  echo "$NEW_TAG" >> "$TAGGED_IMAGE_LIST"
  echo "   • $img → $NEW_TAG"
done <<< "$IMAGE_LIST"

# Replace all image: tags — regardless of current value
sed -i -E \
  -e "s|(image:[[:space:]]+[^[:space:]#]+):[^/:[:space:]]+|\1:${SNAPSHOT_TAG}|g" \
  -e "s|(image:[[:space:]]+[^[:space:]:#]+)$|\1:${SNAPSHOT_TAG}|g" \
  "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
echo "   • All image tags → :${SNAPSHOT_TAG}"

# Set project name at top of docker-compose.yaml
# Replace if name: already exists, otherwise insert at top
if grep -q "^name:" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"; then
  sed -i "s|^name:.*|name: ${SNAPSHOT_TAG}|" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
else
  sed -i "1s|^|name: ${SNAPSHOT_TAG}\n\n|" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
fi
echo "   • Project name → ${SNAPSHOT_TAG}"

# Set container_name for each service
# Reads all service names from compose and sets container_name: projectname-service
SERVICE_NAMES=$(docker compose config --services 2>/dev/null)
while IFS= read -r service; do
  [ -z "$service" ] && continue
  CONTAINER_NAME="${SNAPSHOT_TAG}-${service}"
  # Insert container_name after service: if not already present
  sed -i "/^  ${service}:/{n; /container_name:/!s/^/    container_name: ${CONTAINER_NAME}\n/}" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
done <<< "$SERVICE_NAMES"
echo "   • container_name set for all services"

# Bundle all re-tagged images in a single docker save
echo "   Bundling images..."
xargs docker save < "$TAGGED_IMAGE_LIST" > "$SNAPSHOT_DIR/images.tar"

# Remove temporary tags
while IFS= read -r tagged; do
  docker rmi "$tagged" &>/dev/null || true
done < "$TAGGED_IMAGE_LIST"
rm -f "$TAGGED_IMAGE_LIST"

echo "✅ Images exported"

# ── Export volumes ────────────────────────────
echo ""
echo "💾 Exporting volumes..."

VOLUME_KEYS=$(docker compose config --volumes 2>/dev/null)

if [ -z "$VOLUME_KEYS" ]; then
  echo "ℹ️  No volumes defined — skipping."
else
  # Get resolved config
  RESOLVED_CONFIG=$(docker compose config 2>/dev/null)

  while IFS= read -r vol_key; do
    [ -z "$vol_key" ] && continue

    # Extract custom name: from resolved config
    CUSTOM_NAME=$(echo "$RESOLVED_CONFIG" | \
      awk "/^volumes:/{found=1} found && /^  ${vol_key}:/{getline; if (/name:/) {match(\$0,/name: (.*)/,a); print a[1]}}" \
      2>/dev/null || echo "")

    if [ -n "$CUSTOM_NAME" ]; then
      FULL_VOL_NAME="$CUSTOM_NAME"
      NEW_VOL_NAME="${CUSTOM_NAME}_${TIMESTAMP}"
      echo "   • $vol_key → $NEW_VOL_NAME"

      # Replace name: and add external: true
      sed -i "s|name: ${CUSTOM_NAME}|name: ${NEW_VOL_NAME}|g" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
      sed -i "/^  ${vol_key}:/{n; /external:/!s/^/    external: true\n/}" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
    else
      FULL_VOL_NAME="${PROJECT_NAME}_${vol_key}"
      NEW_VOL_NAME="${FULL_VOL_NAME}_${TIMESTAMP}"
      echo "   • $vol_key → $NEW_VOL_NAME (fallback)"

      # Insert name: and external: true since none exists
      sed -i "/^  ${vol_key}:/{n; /name:/!s/^/    name: ${NEW_VOL_NAME}\n    external: true\n/}" "$SNAPSHOT_DIR/repo/$COMPOSE_FILE"
    fi

    # Check if volume exists
    if ! docker volume inspect "$FULL_VOL_NAME" &>/dev/null; then
      echo "     ⚠️  Volume '$FULL_VOL_NAME' not found — skipping."
      continue
    fi

    # Windows Git Bash fix: // prevents path translation by Git Bash
    docker run --rm \
      -v "${FULL_VOL_NAME}://volume_data" \
      alpine \
      tar czf - -C //volume_data . > "$SNAPSHOT_DIR/volumes/${vol_key}.tar.gz"

    echo "     ✅ exported"

  done <<< "$VOLUME_KEYS"

fi

# ── Bundle everything ─────────────────────────
echo ""
echo "🗜️  Bundling everything..."
tar cf "$FINAL_TAR" -C "/tmp" "$(basename "$SNAPSHOT_DIR")"
rm -rf "$SNAPSHOT_DIR"

SIZE=$(du -sh "$FINAL_TAR" | cut -f1)
echo ""
echo "─────────────────────────────────────────"
echo "✅ Snapshot complete!"
echo "   📁 $(basename "$FINAL_TAR") ($SIZE)"
echo "─────────────────────────────────────────"
