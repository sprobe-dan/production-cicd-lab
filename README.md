# Production CI/CD Lab

[![CI](https://github.com/sprobe-dan/production-cicd-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/sprobe-dan/production-cicd-lab/actions/workflows/ci.yml)

A hands-on project for learning how to build a production-ready CI/CD pipeline using GitHub Actions, Python, Docker, and PostgreSQL.

## Current Pipeline

The CI workflow runs when:

- Code is pushed to `main`
- A pull request targets `main`
- It is manually triggered using `workflow_dispatch`

The pipeline:

1. Runs linting, formatting, Python tests, and a Docker image smoke test.
2. On a successful push to `main`, publishes the tested image to GHCR with a full commit SHA tag.
3. Automatically deploys that image to staging.
4. Deploys the same SHA to production through a manual, protected workflow.

```text
Push to main -> CI and image publish -> staging -> approved production
```

## Documentation

- [VPS and CI/CD setup](docs/vps-cicd-setup.md)
- [Deployment runbook](docs/deployment.md)
- [Rollback runbook](docs/rollback.md)
- [Incident-response runbook](docs/incident-runbook.md)
- [Backup and restore](docs/backup-restore.md)
- [New-environment checklist](docs/new-environment-checklist.md)
