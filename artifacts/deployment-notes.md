# Deployment & Infrastructure Notes

## Stack

- **Container registry**: GHCR (`ghcr.io/landovsky/electricity-tracker`)
- **Cluster**: K3s with Flux CD GitOps (`/Users/tomas/git/projects/k3s`)
- **Domain**: `sepot.kopernici.cz` (Traefik ingress + cert-manager TLS)
- **Image tagging**: Semver tags (`git tag v0.0.X`) trigger CI → GHCR push → Flux auto-deploy

## CI/CD Pipeline (`.github/workflows/ci.yml`)

- Triggers on: `main`, `main-rails` branch pushes + `v*` tags + PRs
- Jobs: `scan_ruby`, `scan_js`, `lint`, `test`, `docker`
- Docker job builds multi-platform image, pushes to GHCR on push events
- Docker build uses Buildx with GitHub Actions cache

## Kubernetes Manifests (`k3s` repo)

All at `apps/sucha-meter/`:
- `deployment.yaml` — Rails container (Thruster on port 80), PVC mount for SQLite, secrets
- `service.yaml` — ClusterIP port 80
- `ingress.yaml` — `sepot.kopernici.cz` with Let's Encrypt TLS
- `pvc.yaml` — 1Gi local-path for SQLite data
- `image-automation/` — Flux ImageRepository + ImagePolicy (semver >=0.0.0) + ImageUpdateAutomation

Flux auto-updates the deployment image tag when new semver tags are pushed.

## Tailwind CSS in Docker — Known Issue & Fix

**Problem**: Running `tailwindcss:build` and `assets:precompile` in a single Rails invocation (`./bin/rails tailwindcss:build assets:precompile`) causes Propshaft to resolve its asset load path **before** `tailwind.css` is written by the Tailwind build step. Result: `tailwind.css` exists in the container at `app/assets/builds/tailwind.css` but is **not** in `public/assets/.manifest.json`, causing `Propshaft::MissingAssetError` at runtime.

**Fix**: Split into two separate `RUN` commands in the Dockerfile:

```dockerfile
# Build Tailwind CSS first
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails tailwindcss:build
# Then precompile (Propshaft discovers tailwind.css on fresh load)
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
```

**Why it works locally but not in Docker**: Locally, `rake assets:clobber tailwindcss:build assets:precompile` works because Rake resolves task dependencies within a single process differently. In Docker, the combined single-command invocation loads Propshaft paths once at boot, before Tailwind writes its output.

**Layout requirement**: The layout must include `<%= stylesheet_link_tag "tailwind" %>` separately from `<%= stylesheet_link_tag :app %>` — this is the `tailwindcss-rails` v4 convention.

## Production Bootstrap

- `lib/tasks/setup.rake` (`app:setup`) — creates Property "Suchá", main + secondary meters, admin user, visitors (Tomas, Petr)
- Runs automatically on container start via `bin/docker-entrypoint` (after `db:prepare`)
- All operations use `find_or_create_by!` — idempotent

## Environment Variables

| Variable | Purpose | Where set |
|---|---|---|
| `SECRET_KEY_BASE` | Rails secret | K8s secret `sucha-meter-secrets` |
| `DISABLE_AUTH` | Skip auth, auto-assign first user | K8s deployment env |
| `ADMIN_EMAIL` | Bootstrap admin user email | K8s deployment env |
| `RECAPTCHA_SITE_KEY` | Google reCAPTCHA v3 site key | K8s secret `sucha-meter-secrets` |
| `RECAPTCHA_SECRET_KEY` | Google reCAPTCHA v3 secret key | K8s secret `sucha-meter-secrets` |
| `GEMINI_API_KEY` | Google Gemini API key | K8s secret `sucha-meter-secrets` |
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | GCP service account JSON | K8s secret `sucha-meter-secrets` |
| `RAILS_ENV` | Production mode | Dockerfile ENV |

## Release Process

```bash
# After committing changes:
git push origin main-rails
git tag v0.0.X
git push origin v0.0.X
# CI builds image → Flux detects new tag → auto-deploys
```

## Resolved Deployment Issues

1. **Image tag not found**: Deployment referenced `0.0.1` but only `sha-*` tags existed. Fix: create semver git tags.
2. **Secret missing**: `CreateContainerConfigError` — `sucha-meter-secrets` didn't exist on cluster. Fix: `kubectl create secret generic`.
3. **Tailwind 500 error**: See "Tailwind CSS in Docker" section above. Fixed in v0.0.4.
4. **Image pull**: `imagePullSecrets: ghcr-secret` must be configured on the deployment.
