# Deployment Runbook

## Release flow

1. Open a pull request.
2. Wait for all CI checks to pass.
3. Merge the pull request into `main`.
4. CI builds and publishes an immutable Docker image tagged with the full Git commit SHA.
5. The staging workflow deploys that image automatically.
6. Verify staging through the `/ready` endpoint.
7. Start the production deployment workflow using the same image SHA.
8. Approve the protected production environment.
9. Verify production through the `/ready` endpoint.

The production image must be the same immutable image that was tested in staging. Do not rebuild the image during production deployment.

## Verify staging

From the deployment server:

```bash
curl --fail http://127.0.0.1:8000/ready

docker inspect \
  --format='{{.Config.Image}}' \
  production-cicd-lab-staging
```

## Verify production

From the deployment server:

```bash
curl --fail http://127.0.0.1:8001/ready

docker inspect \
  --format='{{.Config.Image}}' \
  production-cicd-lab-production
```

## Verify both deployed images

```bash
docker inspect \
  --format='{{.Name}} {{.Config.Image}}' \
  production-cicd-lab-staging \
  production-cicd-lab-production
```

After promotion, staging and production should normally reference the same image SHA.

## Database migrations

Normal deployments run:

```bash
alembic upgrade head
```

Database changes must use backward-compatible expand-and-contract migrations.

Application rollback does not automatically reverse database migrations. Avoid destructive schema changes in the same release that stops using the old schema.

## Deployment state files

Staging:

```text
/opt/production-cicd-lab/.current-image.staging
/opt/production-cicd-lab/.previous-image.staging
```

Production:

```text
/opt/production-cicd-lab/.current-image.production
/opt/production-cicd-lab/.previous-image.production
```

## Current limitations

- Staging and production share one DigitalOcean Droplet.
- Deployments may cause brief application downtime.
- This pipeline is not a zero-downtime or high-availability deployment.
- PostgreSQL backups require a separate backup and restore procedure.
