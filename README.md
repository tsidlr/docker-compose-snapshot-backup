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
├── start.bat   ← Windows: double-click to restore
├── restore.ps1            ← PowerShell restore logic
├── snapshot-info.txt      ← metadata
├── images.tar             ← all Docker images (collision-safe tags)
├── volumes/               ← all named volumes
└── repo/                  ← complete project with patched docker-compose.yaml
```

The recipient (developer, tester, or project manager) extracts the archive and double-clicks `start.bat`. That's it — all containers start immediately with the exact same state.

---

## Features

- **Complete snapshot** — images, volumes, config and repo in one file
- **Collision-safe** — all image tags, volume names, container names and the Compose project name are automatically suffixed with `projectname_timestamp` — multiple snapshots never interfere with each other
- **Auto-patched docker-compose.yaml** — image tags, volume names, container names and `name:` are all rewritten automatically so `docker compose up` works out of the box
- **Windows restore for non-developers** — `start.bat` checks for Docker, gives clear error messages, and starts everything with a double-click
- **Angular dist/ support** — active bind-mounts pointing to local frontend build artifacts are detected and included automatically
- **No registry needed** — everything is self-contained, no access to GitLab/Docker Hub required
- **Works across machines** — path-independent, runs anywhere Docker Desktop is installed

---

## Requirements

**To create a snapshot (developer):**
- Linux, macOS, or Windows with Git Bash / WSL
- Docker + Docker Compose

**To restore a snapshot (developer or non-developer):**
- Windows with [Docker Desktop](https://www.docker.com/products/docker-desktop)

---

## Usage

### Create a snapshot

```bash
# Navigate to your docker-compose project
cd my-project

# Run snapshot.sh from wherever you placed it
../snapshot.sh
```

Output: `snapshot_myproject_20260603_120000.tar`

### Restore a snapshot (Windows)

1. Extract the `.tar` file
2. Double-click `start.bat`
3. Done — all containers start automatically

### Restore a snapshot (Developer / CLI)

```bash
# Extract the tar
tar xf snapshot_myproject_20260603_120000.tar
cd snapshot_myproject_20260603_120000

# Load images
docker load < images.tar

# Restore volumes (repeat for each volume)
docker volume create <volume-name>
docker run --rm -v <volume-name>:/volume_data -v $(pwd)/volumes:/backup \
  alpine sh -c "tar xzf /backup/<volume-key>.tar.gz -C /volume_data"

# Start
cd repo
docker compose up -d
```

---

## How it works

When you run `snapshot.sh`, it:

1. **Copies the repo** into the snapshot
2. **Detects active bind-mounts** pointing to local `dist/` folders (Angular builds) and includes them
3. **Tags all images** with a unique `projectname_timestamp` tag
4. **Patches `docker-compose.yaml`** — rewrites all image tags, volume names, container names and the project `name:` field
5. **Exports all images** into a single `images.tar`
6. **Exports all named volumes** as compressed archives
7. **Generates `start.bat` and `restore.ps1`** inside the snapshot
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

- [ ] Linux/macOS restore script
- [ ] `--exclude-volumes` flag
- [ ] `--exclude-services` flag
- [ ] Checksum verification on restore
- [ ] Upload directly to SharePoint / S3

---

## License

MIT