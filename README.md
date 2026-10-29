# nebula-cti-hunt (umbrella)

One-product local orchestration for **CTI** + **Hunt**. Leaf repos stay standalone; this umbrella only links and starts them.

## Leaf repos (source of truth)

| Leaf | Standalone GitHub | Typical local path (Windows) |
|------|-------------------|------------------------------|
| CTI platform | https://github.com/mohdhw34/cti-platform | `C:\Users\MOHD\Desktop\Projects\CTI` |
| Hunt platform | https://github.com/mohdhw34/hunt-platform | `C:\Users\MOHD\hunt-platform` |

Configure paths in `.env` (copy from `.env.example`). Defaults match Mohamed’s Desktop/Projects layout.

**Do not** treat this umbrella as the place to develop features — open PRs against `cti-platform` / `hunt-platform`.

## Layout options

### A — Documented path links (default)

Keep clones wherever they already live. Point `CTI_ROOT` / `HUNT_ROOT` at them. No git submodule ceremony.

### B — Git submodules (optional)

```bash
git submodule add https://github.com/mohdhw34/cti-platform.git vendors/cti-platform
git submodule add https://github.com/mohdhw34/hunt-platform.git vendors/hunt-platform
git submodule update --init --recursive
```

Then set `CTI_ROOT=./vendors/cti-platform` and `HUNT_ROOT=./vendors/hunt-platform`.

## Ports (loopback)

| Service | Port | URL |
|---------|------|-----|
| cti-core | 8790 | http://127.0.0.1:8790/health |
| hunt-platform | 8788 | http://127.0.0.1:8788/v1/health |
| cti-console (Vite) | 5173 | http://127.0.0.1:5173 |

Console Phase Y Hunt nav → `/cases`, `/detections`. Vite proxies `/hunt-api` → `:8788`. Set `VITE_HUNT_TOKEN` to the same value as hunt’s `NEBULA_HUMAN_TOKEN` (never commit). Offline / unreachable hunt shows a health chip / error banner on Cases — Intel still works.

## Quick start

```powershell
cd C:\Users\MOHD\Desktop\Projects\nebula-cti-hunt
copy .env.example .env
# edit .env: CTI_ROOT, HUNT_ROOT, VITE_HUNT_TOKEN / NEBULA_HUMAN_TOKEN (no secrets in git)
.\scripts\start-stack.ps1
```

Stop:

```powershell
.\scripts\stop-stack.ps1
```

Compose (optional; path-mounts leaves — requires Docker Desktop):

```powershell
docker compose up --build
```

## Secrets

Never commit tokens. Operator env only:

- `NEBULA_HUMAN_TOKEN` / `VITE_HUNT_TOKEN` — hunt `X-Nebula-Token`
- `CTI_API_TOKEN` / `VITE_CTI_API_TOKEN` — when cti-core auth enabled
- Provider keys stay in each leaf’s own `.env` / secrets file

## Related merges

- hunt-platform [#2](https://github.com/mohdhw34/hunt-platform/pull/2)
- cti-platform [#30](https://github.com/mohdhw34/cti-platform/pull/30), [#31](https://github.com/mohdhw34/cti-platform/pull/31), Phase Y [#32](https://github.com/mohdhw34/cti-platform/pull/32)
