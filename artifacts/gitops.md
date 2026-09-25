# GitOps & Deployment

## Overview

Sucha Meter (Electricity Tracker) deploys to a self-hosted K3s cluster via Flux GitOps. Push a semver tag, Docker image builds in CI, Flux detects the new tag, deployment updates automatically.

## Repositories

| Repo | Purpose | Path |
|------|---------|------|
| `sucha-meter-vol1` | Application source code | `/Users/tomas/git/ai/sucha-meter-vol1` |
| K3s cluster repo | Kubernetes manifests, Flux config | `/Users/tomas/git/k3s/` |
| K3s app manifests | This app's k8s resources | `/Users/tomas/git/k3s/apps/sucha-meter/` |
| Flux cluster entry | Kustomization reference | `/Users/tomas/git/k3s/clusters/production/apps/sucha-meter.yaml` |

## Hostnames

| Domain | Purpose |
|--------|---------|
| `sepot.kopernici.cz` | Primary (Suchá property) |
| `tymlova.kopernici.cz` | Secondary (Tymlova property) |

Both share the same deployment and TLS certificate (`sucha-meter-tls`).

## Release Flow

```
git tag v0.2.9 → push tag
    ↓
GitHub Actions CI triggers (ci.yml)
    ↓
Quality gates: Brakeman, bundler-audit, importmap audit, RuboCop, RSpec
    ↓
Docker job builds image → pushes to GHCR
    ghcr.io/landovsky/electricity-tracker:0.2.9
    ↓
Flux ImageRepository scans GHCR
    ↓
Flux ImagePolicy picks latest semver >=0.0.0
    ↓
Flux ImageUpdateAutomation commits new tag to
    apps/sucha-meter/deployment.yaml (k3s repo)
    ↓
Flux reconciles → pod restarts with new image
```

### Release Commands

```bash
# Using release-it (preferred):
npx release-it --ci

# Manual:
git tag v0.2.9
git push origin v0.2.9
```

**release-it config** (`.release-it.json`): Creates git tag `v${version}`, pushes, creates GitHub release. No npm publish.

## CI/CD Pipeline

### `.github/workflows/ci.yml`

Triggers on: PRs, pushes to `main`/`main-rails`, `v*` tags.

| Job | What it does |
|-----|-------------|
| `scan_ruby` | Brakeman (security) + bundler-audit (CVEs) |
| `scan_js` | `importmap audit` (JS dependency CVEs) |
| `lint` | RuboCop with GitHub formatter |
| `test` | RSpec with SQLite, Tailwind build |
| `docker` | Build & push to GHCR (after all gates pass, push events only) |

Docker image tags: `<semver>`, `sha-<hash>`, `latest` (default branch).

## Container

### Dockerfile (multi-stage)

1. **Base**: Ruby 3.4.7-slim, curl, libjemalloc2, libvips, sqlite3
2. **Build**: Install gems (production only), bootsnap precompile, Tailwind build, asset precompile (split into two `RUN` steps — see deployment-notes.md for why)
3. **Final**: Non-root `rails:rails` user (UID 1000), Thruster on port 80

**CMD**: `./bin/thrust ./bin/rails server`
**Entrypoint**: `bin/docker-entrypoint` (runs `db:prepare` + `app:setup`; the latter seeds only an empty DB)

## Kubernetes Resources

All manifests in `/Users/tomas/git/k3s/apps/sucha-meter/`.

### Deployment (`deployment.yaml`)

- Single replica, namespace `default` (**keep it at 1 process** — login rate limits are per-process, see Known Issues)
- Image: `ghcr.io/landovsky/electricity-tracker:<tag>` (auto-updated by Flux)
- Container port: 80 (Thruster)
- PVC mount: `/rails/storage` for SQLite persistence
- Image pull secret: `ghcr-secret`
- Priority class: `default-priority`
- Resources:
  - Requests: 200m CPU, 256Mi memory
  - Limits: 500m CPU, 512Mi memory

### Service (`service.yaml`)

- ClusterIP `10.43.238.68`, port 80

### Ingress (`ingress.yaml`)

- Traefik ingress class
- Hosts: `sepot.kopernici.cz`, `tymlova.kopernici.cz`
- TLS via cert-manager (`letsencrypt-production` cluster issuer)
- HTTPS redirect middleware: `default-redirect-https@kubernetescrd`

### Storage (`pvc.yaml`)

- PVC `sucha-meter-db`: 1Gi, `local-path` storage class, RWO
- Stores SQLite production database at `/rails/storage/`

### Flux Image Automation (`image-automation/`)

| Resource | Details |
|----------|---------|
| `imagerepository.yaml` | Scans `ghcr.io/landovsky/electricity-tracker` |
| `imagepolicy.yaml` | Semver `>=0.0.0` |
| `imageupdateautomation.yaml` | Commits tag updates to k3s repo |

## Secrets

### K8s Secret: `sucha-meter-secrets`

| Key | Purpose |
|-----|---------|
| `SECRET_KEY_BASE` | Rails secret key |
| `SMS_MANAGER_API_KEY` | SMS notifications |
| `GMAIL_APP_PASSWORD` | Email delivery via Gmail |
| `RECAPTCHA_SITE_KEY` | Google reCAPTCHA v3 (frontend) |
| `RECAPTCHA_SECRET_KEY` | Google reCAPTCHA v3 (backend) |
| `GEMINI_API_KEY` | Google Gemini API |
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | GCP service account JSON |
| `DO_S3_KEY_ID` | DigitalOcean Spaces access key |
| `DO_S3_SECRET_KEY` | DigitalOcean Spaces secret key |

### Other Secrets

| Secret | Purpose |
|--------|---------|
| `ghcr-secret` | GHCR image pull authentication |
| `sucha-meter-tls` | TLS certificate (managed by cert-manager) |

## Environment Variables (Production)

| Variable | Source | Purpose |
|----------|--------|---------|
| `RAILS_ENV` | Hardcoded `production` | Rails environment |
| `APP_HOST` | Deployment env | `https://sepot.kopernici.cz` |
| `ADMIN_EMAIL` | Deployment env | Bootstrap admin user (`tomas@kopernici.cz`) |
| `DATABASE_URL` | Deployment env | `sqlite3:///rails/storage/production.sqlite3` |
| `SECRET_KEY_BASE` | Secret | Rails credential encryption |
| `SMS_MANAGER_API_KEY` | Secret | SMS delivery |
| `GMAIL_APP_PASSWORD` | Secret | Email delivery |
| `RECAPTCHA_SITE_KEY` | Secret | reCAPTCHA frontend |
| `RECAPTCHA_SECRET_KEY` | Secret | reCAPTCHA backend |
| `GEMINI_API_KEY` | Secret | AI features |
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | Secret | GCP services |
| `DO_S3_KEY_ID` | Secret | Object storage |
| `DO_S3_SECRET_KEY` | Secret | Object storage |

## Production Bootstrap

`lib/tasks/setup.rake` (`app:setup`) seeds the initial Property, meters, users, visitors and historical stays. Runs automatically on container start via `bin/docker-entrypoint` (after `db:prepare`), but is a **first-boot-only** bootstrap: when any property already exists it logs "Database already bootstrapped" and exits, so deploys and pod restarts never overwrite, re-create or re-grant anything admins changed.

The admin "Import XLS" action (`XlsDataMigration`) wipes and re-imports all data. It is refused while stays/readings/manual entries exist unless `ALLOW_DESTRUCTIVE_XLS_MIGRATION=true` is set on the deployment (not set in production — keep it that way).

## Known Issues

- GHCR package must be **public** for Flux ImageRepository scans to work (or configure `ghcr-secret` in flux-system namespace)
- Tailwind CSS Docker build requires split `RUN` commands — see `artifacts/deployment-notes.md`
- `imagePullSecrets: ghcr-secret` must exist in the deployment namespace
- **Login rate limits are in-process memory.** `SessionsController::RATE_LIMIT_STORE` is an `ActiveSupport::Cache::MemoryStore`, so the throttles on `POST /prihlaseni`, `/prihlaseni/sms` and `/prihlaseni/overeni` (per IP and per e-mail) are counted separately in every Puma worker/pod. They silently weaken (limit × processes) if `WEB_CONCURRENCY` or `replicas` is ever raised above 1 — switch the store to a shared cache (e.g. Solid Cache) before scaling. Per-IP limits also rely on the real client IP reaching Rails (Traefik `externalTrafficPolicy: Local`).
- **Allowed hosts are hard-coded.** `config.x.app_hosts` in `config/environments/production.rb` lists `sepot.kopernici.cz`, `tymlova.kopernici.cz` and the `APP_HOST` host; any new ingress hostname must be added there or requests get 403 (`/up` is exempt for probes). Magic-link e-mails are only built on these hosts.
