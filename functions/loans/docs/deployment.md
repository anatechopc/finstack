# Deployment

## Branch-to-Environment Mapping

Deployment is automated via GitHub Actions. Pushing to a branch triggers the corresponding workflow:

| Branch | Environment | GCP Project | Collection Prefix |
|---|---|---|---|
| `develop` | development | `loooans-dev-stg` | `dev_` |
| `release/**` | staging | `loooans-dev-stg` | `stg_` |
| `master` | production | `loooans-prod` | (none) |

## Environment Variable

The `ENVIRONMENT` env var is **required** at runtime. Valid values: `development`, `staging`, `production`. The app exits if it's not set.

## Manual Deployment

```bash
.github/scripts/deploy_functions.sh -e <environment> -p <project>
```

## CI/CD Pipeline

GitHub Actions workflows in `.github/workflows/`:

- **Build + test** on every push and PR
- **Deploy** runs only on push (not PRs)
- Uses **OIDC workload identity federation** for GCP auth (no service account keys)
