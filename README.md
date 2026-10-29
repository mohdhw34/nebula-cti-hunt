# nebula-cti-hunt (umbrella)

One-command local orchestration for **CTI** + **Hunt**. Leaf repos stay standalone; this umbrella only links and starts them.

## Leaf repos (source of truth)

| Leaf | Standalone GitHub | Typical local path (Windows) |
|------|-------------------|------------------------------|
| CTI platform | https://github.com/mohdhw34/cti-platform | `C:\Users\MOHD\Desktop\Projects\CTI` |
| Hunt platform | https://github.com/mohdhw34/hunt-platform | `C:\Users\MOHD\hunt-platform` |

Configure paths in `.env` (copy from `.env.example`). Defaults match Mohamed’s Desktop/Projects layout.

**Do not** treat this umbrella as the place to develop features — open PRs against `cti-platform` / `hunt-platform`.

## Ports (loopback)

| Service | Port | Health / access |
|---------|------|-----------------|
| cti-console (Vite) | **5173** | http://127.0.0.1:5173 |
| cti-core | **8790** | http://127.0.0.1:8790/health |
| hunt-api (platform) | **8788** | http://127.0.0.1:8788/v1/health |
| intel-core (hunt leaf) | **8787** | http://127.0.0.1:8787/v1/health |

`scripts/dev.sh` in hunt-platform starts **both** intel-core and hunt-api. Start scripts reuse listeners if a live soak / sibling agent already owns those ports.

Console Hunt nav → `/cases`, `/detections`. Vite proxies `/hunt-api` → `:8788`. Set `VITE_HUNT_TOKEN` to the same value as hunt’s `NEBULA_HUMAN_TOKEN` (never commit). Offline / unreachable hunt shows a health chip on Cases — Intel still works.

## Quick start (one command)

```powershell
cd C:\Users\MOHD\Desktop\Projects\nebula-cti-hunt
copy .env.example .env
# edit .env: CTI_ROOT, HUNT_ROOT, tokens (values never printed by scripts)
.\start.ps1
```

Bash / WSL:

```bash
cd /mnt/c/Users/MOHD/Desktop/Projects/nebula-cti-hunt
cp .env.example .env
# edit .env …
chmod +x start.sh scripts/*.sh
./start.sh
```

Status / stop:

```powershell
.\scripts\status.ps1
.\scripts\stop-stack.ps1
```

Reuse-only (coordinate with a live stack — do not start leaves):

```powershell
$env:NEBULA_REUSE_ONLY = "1"
.\start.ps1
```

Compose (`docker-compose.yml`) remains a draft until leaf Dockerfiles ship. Prefer `start.ps1` / `start.sh`.

## Secrets

Never commit tokens. Operator env only (umbrella `.env` is gitignored):

- `NEBULA_HUMAN_TOKEN` / `VITE_HUNT_TOKEN` — hunt `X-Nebula-Token`
- `CTI_API_TOKEN` / `VITE_CTI_API_TOKEN` — when cti-core auth enabled
- Provider keys stay in each leaf’s own secrets file (`HUNT_NO_SECRETS=1` by default in start scripts)

Scripts load `.env` into the process and pass Vite vars to the console child — they **do not** write `.env.local` into leaf checkouts (so sibling workers can own CTI/hunt trees safely).

## Layout options

### A — Documented path links (default)

Keep clones wherever they already live. Point `CTI_ROOT` / `HUNT_ROOT` at them.

### B — Git submodules (optional)

```bash
git submodule add https://github.com/mohdhw34/cti-platform.git vendors/cti-platform
git submodule add https://github.com/mohdhw34/hunt-platform.git vendors/hunt-platform
git submodule update --init --recursive
```

Then set `CTI_ROOT=./vendors/cti-platform` and `HUNT_ROOT=./vendors/hunt-platform`.

## Related merges

- hunt-platform [#2](https://github.com/mohdhw34/hunt-platform/pull/2)
- cti-platform Phase Y [#32](https://github.com/mohdhw34/cti-platform/pull/32) and later Settings/Hunt nav work
