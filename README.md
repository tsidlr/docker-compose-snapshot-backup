# docker-compose-snapshot-backup

**Instantly snapshot and share your entire Docker Compose environment — images, volumes, config and all — in a single file.**

No registry access required. No complex setup. One script, one file, one double-click to restore.

---

## The Problem

When working in teams with Docker Compose, sharing a local environment is painful:

- Testers can't test a feature until it's merged and deployed to a test system
- Merge conflicts block features from being deployed — creating a testing bottleneck
- "Works on my machine" is hard to debug without the exact same environment

## The Solution

`snapshot.sh` creates a fully self-contained snapshot of your Docker Compose environment:

```bash
cd my-project
../snapshot.sh
```

This produces a single `.tar` file containing:

```
snapshot_myproject_20260603_120000.tar
├── start.bat              ← Windows: double-click to restore
├── restore.ps1            ← PowerShell restore logic
├── restore.sh             ← Linux / macOS restore script
├── snapshot-info.txt      ← metadata
├── images.tar             ← all Docker images (collision-safe tags)
├── volumes/               ← all named volumes
└── repo/                  ← complete project with patched docker-compose.yaml
```

The recipient extracts the archive and runs the restore script for their platform. All containers start immediately with the exact same state.

---

## Features

- **Complete snapshot** — images, volumes, config and repo in one file
- **Collision-safe** — all image tags, volume names, container names and the Compose project name are automatically suffixed with `projectname_timestamp` — multiple snapshots never interfere with each other
- **Auto-patched docker-compose.yaml** — image tags, volume names, container names and `name:` are all rewritten automatically so `docker compose up` works out of the box
- **One-command restore** — `start.bat` (Windows double-click) or `./restore.sh` (Linux/macOS) — checks for Docker, gives clear error messages, starts everything automatically
- **Angular dist/ support** — active bind-mounts pointing to local frontend build artifacts are detected and included automatically
- **No registry needed** — everything is self-contained, no access to GitLab/Docker Hub required
- **Works across machines** — path-independent, runs anywhere Docker Desktop is installed

---

## Requirements

**To create a snapshot (developer):**
- Linux, macOS, or Windows with Git Bash / WSL
- Docker + Docker Compose

**To restore a snapshot:**
- Any OS with [Docker Desktop](https://www.docker.com/products/docker-desktop) (or Docker Engine on Linux)

---

## Usage

### Create a snapshot (Linux / macOS)

```bash
# Download the script (once)
curl -O https://raw.githubusercontent.com/tsidlr/docker-compose-snapshot-backup/main/snapshot.sh
chmod +x snapshot.sh

# Navigate to your docker-compose project and run it
cd my-project
../snapshot.sh
```

### Create a snapshot (Windows — Git Bash or WSL)

```bash
# Download the script (once)
curl -O https://raw.githubusercontent.com/tsidlr/docker-compose-snapshot-backup/main/snapshot.sh

# Navigate to your docker-compose project and run it
cd my-project
bash ../snapshot.sh
```

Output: `snapshot_myproject_20260603_120000.tar`

---

### Restore a snapshot (Windows)

#### Step 1 — Extract the `.tar` file

Windows 11 has `tar` built in — run in PowerShell or CMD:

```powershell
tar xf snapshot_myproject_20260603_120000.tar
```

On older Windows, use [7-Zip](https://www.7-zip.org) to extract.

#### Step 2 — Run the restore

Open the extracted folder and double-click `start.bat`. The script will:

- Check if Docker Desktop is installed and running
- Load all images
- Restore all volumes
- Start all containers

Done — all containers are running.

---

### Restore a snapshot (Linux / macOS)

```bash
tar xf snapshot_myproject_20260603_120000.tar
cd snapshot_myproject_20260603_120000
./restore.sh
```

The script checks for Docker, loads images, restores volumes and starts all containers — same behavior as on Windows.

---

## How it works

When you run `snapshot.sh`, it:

1. **Copies the repo** into the snapshot
2. **Detects active bind-mounts** pointing to local `dist/` folders (Angular builds) and includes them
3. **Tags all images** with a unique `projectname_timestamp` tag
4. **Patches `docker-compose.yaml`** — rewrites all image tags, volume names, container names and the project `name:` field
5. **Exports all images** into a single `images.tar`
6. **Exports all named volumes** as compressed archives
7. **Generates `start.bat`, `restore.ps1` and `restore.sh`** inside the snapshot
8. **Packs everything** into one `.tar` file

The result: a fully portable, collision-safe snapshot that works on any machine with Docker Desktop — no external dependencies, no registry access, no manual configuration.

---

## Why not existing tools?

| Tool | Images | Volumes | Auto-patches compose | Collision-safe | Windows 1-click restore |
|---|---|---|---|---|---|
| docker-vackup | ❌ | ✅ | ❌ | ❌ | ❌ |
| docker-compose-full-backup | ✅ | ✅ | ❌ | ❌ | ❌ |
| docker-backup (muesli) | ✅ | ✅ | ❌ | ❌ | ❌ |
| **docker-compose-snapshot-backup** | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Use Cases

- **Share a feature branch** with a tester or PM before it's merged
- **Unblock testing** when merge conflicts stall deployment to test systems
- **Reproduce a bug** by sharing the exact environment where it occurred
- **Onboard new developers** with a ready-to-run environment
- **Archive a release** state for later reference

---

## Roadmap

- [ ] `--exclude-volumes` flag
- [ ] `--exclude-services` flag
- [ ] Checksum verification on restore
- [ ] Upload directly to SharePoint / S3

---

## License

MIT