# Rollback Runbook

## When to roll back

Roll back when a deployment causes:

- Failed readiness or smoke checks
- Application errors affecting normal use
- A severe regression
- An application version incompatible with the current environment

Do not wait for a complete outage if the deployed release is clearly unsafe.

## Preferred rollback procedure

1. Open the repository on GitHub.
2. Go to **Actions**.
3. Select the **Rollback** workflow.
4. Select **Run workflow**.
5. Choose `staging` or `production`.
6. Start the workflow.
7. Approve the protected production environment when rolling back production.
8. Wait for the readiness verification to succeed.

The workflow deploys the image stored in the environment's previous-image state file.

## State files

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

## Verify staging after rollback

```bash
curl --fail http://127.0.0.1:8000/ready

docker inspect \
  --format='{{.Config.Image}}' \
  production-cicd-lab-staging
```

## Verify production after rollback

```bash
curl --fail http://127.0.0.1:8001/ready

docker inspect \
  --format='{{.Config.Image}}' \
  production-cicd-lab-production
```

## Emergency server-side rollback

Use this only if GitHub Actions is unavailable.

Connect as the deployment user:

The key path below is the staging deployment identity created in [VPS setup](vps-cicd-setup.md); either authorized deployment identity can connect to this shared host.

```bash
ssh \
  -i ~/.ssh/production_cicd_lab_staging \
  deploy@YOUR_DROPLET_IP
```

Then run one of:

```bash
cd /opt/production-cicd-lab
./rollback.sh staging
```

```bash
cd /opt/production-cicd-lab
./rollback.sh production
```

## Database warning

Rollback restores the previous application image but does not downgrade the database.

Rollback deployments skip migrations because an older application image may not recognize migrations introduced by a newer release.

Database migrations must therefore remain backward-compatible. Any database restoration or migration downgrade must be treated as a separate, explicitly reviewed operation.

## Restore the latest release

After diagnosing and correcting the problem, run the normal deployment workflow using the intended full image SHA.

Verify `/ready` after restoring the release.
