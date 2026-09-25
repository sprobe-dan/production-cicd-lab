# Incident Response Runbook

## Purpose

Use this runbook when staging or production is unavailable, unhealthy, or behaving incorrectly after a deployment.

The priorities are:

1. Protect users and data.
2. Stop further deployments.
3. Determine whether the latest release caused the incident.
4. Restore a known working version.
5. Preserve enough evidence to understand the cause.
6. Document the incident and preventive actions.

## Initial response

1. Record the time the problem was detected.
2. Record which environment is affected: staging, production, or both.
3. Pause new deployments until the environment is stable.
4. Check the external readiness endpoint.
5. Connect to the Droplet as the `deploy` user.
6. Inspect container status, health, logs, disk space, and memory.
7. Roll back if the incident began after a release and the previous image is known to work.

Do not print secrets, environment files, private keys, or database passwords while investigating.

## Quick diagnosis

### Check external endpoints

Use the public staging and production URLs configured for the project:

```bash
curl --fail --show-error STAGING_URL/health
curl --fail --show-error STAGING_URL/ready

curl --fail --show-error PRODUCTION_URL/health
curl --fail --show-error PRODUCTION_URL/ready
```

### Connect to the server

```bash
ssh \
  -i ~/.ssh/production_cicd_lab \
  deploy@YOUR_DROPLET_IP
```

### Check all relevant containers

```bash
docker ps -a \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}'
```

Expected application containers:

```text
production-cicd-lab-staging
production-cicd-lab-production
```

Expected database containers:

```text
production-cicd-lab-postgres-staging
production-cicd-lab-postgres-production
```

### Check internal health and readiness

```bash
curl --fail --show-error http://127.0.0.1:8000/health
curl --fail --show-error http://127.0.0.1:8000/ready

curl --fail --show-error http://127.0.0.1:8001/health
curl --fail --show-error http://127.0.0.1:8001/ready
```

Interpretation:

| Result | Likely area |
| --- | --- |
| `/health` fails | Application container or process |
| `/health` passes but `/ready` fails | Database connectivity or readiness |
| Internal checks pass but public URL fails | Nginx, firewall, DNS, or network |
| Both environments fail | Shared Droplet, Docker, disk, memory, or network |

### Inspect application logs

```bash
docker logs \
  --timestamps \
  --tail 200 \
  production-cicd-lab-staging
```

```bash
docker logs \
  --timestamps \
  --tail 200 \
  production-cicd-lab-production
```

### Inspect database logs

```bash
docker logs \
  --timestamps \
  --tail 200 \
  production-cicd-lab-postgres-staging
```

```bash
docker logs \
  --timestamps \
  --tail 200 \
  production-cicd-lab-postgres-production
```

### Check server resources

```bash
df -h
free -h
docker stats --no-stream
```

A full disk or exhausted memory can prevent containers and PostgreSQL from operating normally.

### Confirm deployed images

```bash
docker inspect \
  --format='{{.Name}} {{.Config.Image}}' \
  production-cicd-lab-staging \
  production-cicd-lab-production
```

Compare the image SHAs with the most recent GitHub Actions deployment runs.

## Recovery decisions

### Latest deployment caused the incident

Run the GitHub Actions rollback workflow for the affected environment.

For production:

1. Select the `production` environment.
2. Approve the protected environment.
3. Wait for the rollback and readiness verification.
4. Verify the public production endpoint.

If GitHub Actions is unavailable, follow the emergency server-side procedure in `docs/rollback.md`.

### Application is healthy but readiness fails

Investigate the database container and connection configuration.

Check:

- PostgreSQL container health
- Database logs
- Available disk space
- Docker network connectivity
- Whether the expected database is running
- Whether the application and database belong to the intended environment

Do not reset, delete, or recreate production database volumes during initial diagnosis.

### Internal checks pass but the public endpoint fails

Check Nginx:

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
```

Review recent Nginx errors:

```bash
sudo journalctl \
  --unit nginx \
  --since '30 minutes ago' \
  --no-pager
```

Also check the DigitalOcean firewall and host firewall rules.

### SSH deployment fails

Check:

- The Droplet is reachable.
- The workflow uses the correct environment.
- The correct environment-scoped private key is configured.
- The matching public key remains in the `deploy` user's `authorized_keys`.
- The known-hosts secret matches the current server host key.
- The deployment user can access Docker.
- The server has sufficient disk space.

Do not disable strict host-key checking as a shortcut.

## Verification after recovery

Recovery is complete only when:

- The affected containers are running and healthy.
- Internal `/health` succeeds.
- Internal `/ready` succeeds.
- The external readiness endpoint succeeds.
- The expected immutable image SHA is deployed.
- No repeated critical errors appear in recent logs.
- Staging and production databases remain intact.

## Incident record

Record the following in an issue or incident note:

```text
Title:
Date and time detected:
Environment:
Reported by:
User impact:
Symptoms:
Deployed image SHA:
Previous image SHA:
Timeline:
Immediate cause:
Root cause:
Recovery action:
Database impact:
Duration:
Preventive actions:
Owner:
```

Never include passwords, tokens, private keys, or complete environment-file contents in the incident record.

## After the incident

1. Create a reproducible test for the failure when practical.
2. Fix the underlying cause in a pull request.
3. Confirm CI detects the failure.
4. Deploy the corrected image to staging.
5. Verify staging before promoting the same image to production.
6. Update the runbooks if the response procedure was incomplete.
