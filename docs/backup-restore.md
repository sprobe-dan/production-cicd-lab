# PostgreSQL backup and restore

An untested backup is not reliable. Test restoration on a separate, controlled host before treating an archive as recoverable. This runbook is documentation; do not run its restore steps against a live environment without an incident-specific plan. See [VPS setup](vps-cicd-setup.md), [deployment](deployment.md), and [incident response](incident-runbook.md).

## Scope and safeguards

Back up each PostgreSQL database separately with `pg_dump`, plus protected `/opt/production-cicd-lab/.env.staging` and `.env.production`, the two Compose files, deployment scripts, Nginx site configuration and TLS renewal details, and release-state files. Keep credentials and application data encrypted off-server with limited access. Store encryption recovery material separately. The Docker named volumes (`production-cicd-lab_postgres_data` for staging and `production-cicd-lab-production_postgres_data` for production) hold physical database data; a copied live volume is not a substitute for a consistent logical dump. Never delete or overwrite a volume during backup.

Do not print an environment file or password. These commands connect through the existing PostgreSQL container's local socket as `cicd_user`; the password stays in the protected Compose environment file and is not passed on the command line. Run as `deploy` on the Ubuntu VPS unless stated otherwise. Ensure the `deploy` account and its backup destination are protected: membership in the `docker` group has root-equivalent host access.

| Environment | Compose project | Compose file | DB container |
| --- | --- | --- | --- |
| staging | `production-cicd-lab` | `compose.staging.yml` | `production-cicd-lab-postgres-staging` |
| production | `production-cicd-lab-production` | `compose.production.yml` | `production-cicd-lab-postgres-production` |

## Create and verify backups

**Ubuntu VPS as deploy, staging:** the directory and archive are private. `pg_dump -Fc` produces a portable custom-format logical archive. Check free disk space first. The timestamp is UTC.

~~~bash
set -euo pipefail
umask 077
install -d -m 700 /opt/production-cicd-lab/backups/staging
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/opt/production-cicd-lab/backups/staging/cicd_lab-staging-$STAMP.dump"
docker compose --project-name production-cicd-lab --env-file /opt/production-cicd-lab/.env.staging --file /opt/production-cicd-lab/compose.staging.yml exec -T db pg_dump -U cicd_user -d cicd_lab -Fc > "$BACKUP"
test -s "$BACKUP"
docker compose --project-name production-cicd-lab --env-file /opt/production-cicd-lab/.env.staging --file /opt/production-cicd-lab/compose.staging.yml exec -T db pg_restore -l < "$BACKUP" > /dev/null
sha256sum "$BACKUP" > "$BACKUP.sha256"
ls -lh "$BACKUP" "$BACKUP.sha256"
~~~

**Ubuntu VPS as deploy, production:** use the production project and protected file. A successful exit from `pg_dump` plus `pg_restore -l` verifies archive structure, not data recoverability.

~~~bash
set -euo pipefail
umask 077
install -d -m 700 /opt/production-cicd-lab/backups/production
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/opt/production-cicd-lab/backups/production/cicd_lab-production-$STAMP.dump"
docker compose --project-name production-cicd-lab-production --env-file /opt/production-cicd-lab/.env.production --file /opt/production-cicd-lab/compose.production.yml exec -T db pg_dump -U cicd_user -d cicd_lab -Fc > "$BACKUP"
test -s "$BACKUP"
docker compose --project-name production-cicd-lab-production --env-file /opt/production-cicd-lab/.env.production --file /opt/production-cicd-lab/compose.production.yml exec -T db pg_restore -l < "$BACKUP" > /dev/null
sha256sum "$BACKUP" > "$BACKUP.sha256"
ls -lh "$BACKUP" "$BACKUP.sha256"
~~~

To list an archive's table and schema entries without displaying rows, run `pg_restore -l` through the matching database container, replacing `BACKUP_FILE` with the chosen protected archive path:

~~~bash
docker exec -i production-cicd-lab-postgres-staging pg_restore -l < BACKUP_FILE
~~~

For a production archive, use `production-cicd-lab-postgres-production` instead. Check the saved checksum with `sha256sum -c BACKUP_FILE.sha256` from the archive's directory. An archive listing and checksum cannot prove that restoration works.

## Restore test on an isolated VPS

**Database-state warning:** `pg_restore` changes the target database. Use a separate recovery VPS or isolated test host with no production DNS or traffic. Never point these commands at either live Compose project or a live Docker volume. Confirm the chosen backup, target host, and recovery window before starting. Preserve the original archive and checksum.

On the recovery host, securely copy the chosen dump and checksum into a mode-700 directory and verify `sha256sum -c`. Install Docker and copy [the generic Compose template](../deploy/templates/compose.environment.yml) to `/opt/production-cicd-lab/compose.environment.yml`. Create a mode-600 `/opt/production-cicd-lab/recovery.env` with fresh `DB_PASSWORD` (64 lowercase hex characters), a published `APP_IMAGE`, `ENVIRONMENT=recovery` and an unused `APP_PORT`. Use the template's unique Compose project `production-cicd-lab-recovery`. Keep its database off public ports. The original environment password is not needed for a logical restore into a new database.

**Ubuntu recovery VPS as its deployment operator:** replace `BACKUP_FILE` with the copied archive's absolute path. The target database must be disposable; `--clean --if-exists` removes matching existing objects in this **recovery database** before recreation.

~~~bash
set -euo pipefail
docker compose --project-name production-cicd-lab-recovery --env-file /opt/production-cicd-lab/recovery.env --file /opt/production-cicd-lab/compose.environment.yml up --detach --wait db
docker compose --project-name production-cicd-lab-recovery --env-file /opt/production-cicd-lab/recovery.env --file /opt/production-cicd-lab/compose.environment.yml exec -T db pg_restore -U cicd_user -d cicd_lab --clean --if-exists --exit-on-error < BACKUP_FILE
docker compose --project-name production-cicd-lab-recovery --env-file /opt/production-cicd-lab/recovery.env --file /opt/production-cicd-lab/compose.environment.yml exec -T db psql -U cicd_user -d cicd_lab -Atc 'SELECT version_num FROM alembic_version'
~~~

Expected: `pg_restore` exits successfully and `alembic_version` returns the expected single revision. Start the recovery `api` only if the image's schema is compatible with the archive, then check `/health` and `/ready` on the recovery host's chosen loopback port. Check expected table counts and a sample of non-sensitive records against known expectations. Record archive SHA256, restore date, image SHA, Alembic revision, checks performed, and result in a private operations log. Remove the disposable recovery environment only after the test is recorded; confirm its exact project and volume before any deletion.

## Production restore decision

**High-impact warning:** a production restore overwrites database state and may lose writes newer than the archive. Stop writes, record the current state, take a fresh pre-restore dump, determine the recovery point and application schema compatibility, notify stakeholders, and approve a maintenance window. Verify the archive in the isolated recovery environment first. Do not use an old application image with an incompatible schema; image rollback does not downgrade the database. Execute a production restore only under a separate incident plan with exact target checks and a recovery path. Never run `docker compose down -v` or delete the production volume as a shortcut.

## Off-server copies, retention, and scheduling

Transfer encrypted archives and protected configuration to a separate account or provider. Restrict access, enable versioning or immutable retention where available, monitor copy failures and free space, and periodically test a restored off-server copy. A reasonable starting policy is daily backups retained 7 days, weekly backups retained 4 weeks, and monthly backups retained 3 months; adjust for data value, regulation, storage cost, and recovery objectives. Keep staging and production retention separate. Do not let a local retention job erase the only usable copy.

For scheduling, save this example as a root-owned, mode-755 `/usr/local/sbin/production-cicd-backup` on the Ubuntu VPS and run it as `deploy`. Test its logic in a controlled window before adding cron. It keeps staging and production separate, fails on errors, and does not disclose the password:

~~~bash
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
case "${1:-}" in
  staging)
    project=production-cicd-lab
    env_file=/opt/production-cicd-lab/.env.staging
    compose_file=/opt/production-cicd-lab/compose.staging.yml
    ;;
  production)
    project=production-cicd-lab-production
    env_file=/opt/production-cicd-lab/.env.production
    compose_file=/opt/production-cicd-lab/compose.production.yml
    ;;
  *) echo 'Usage: production-cicd-backup staging|production' >&2; exit 2 ;;
esac
directory="/opt/production-cicd-lab/backups/$1"
install -d -m 700 "$directory"
archive="$directory/cicd_lab-$1-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker compose --project-name "$project" --env-file "$env_file" --file "$compose_file" exec -T db pg_dump -U cicd_user -d cicd_lab -Fc > "$archive"
test -s "$archive"
docker compose --project-name "$project" --env-file "$env_file" --file "$compose_file" exec -T db pg_restore -l < "$archive" > /dev/null
sha256sum "$archive" > "$archive.sha256"
~~~

Example `deploy` crontab entries, once that script exists and has been tested:

**Ubuntu VPS as deploy:** open the crontab with `crontab -e` and add:

~~~cron
0 2 * * * /usr/local/sbin/production-cicd-backup staging
30 2 * * * /usr/local/sbin/production-cicd-backup production
~~~

`production-cicd-backup` is an example script in this runbook, not a file supplied by this repository. Arrange alerting for nonzero exits and off-server transfer failures. Do not schedule the cron entries until the reviewed script exists.

## Restore test checklist

- [ ] Archive and checksum copied from off-server storage; checksum matches.
- [ ] Target host, Compose project, volume, port, and database confirmed isolated.
- [ ] `pg_restore -l` lists expected objects.
- [ ] Restore exits without errors; Alembic revision matches the expected release.
- [ ] Representative table counts and non-sensitive records checked.
- [ ] Recovery app `/health` and `/ready` pass with a compatible image.
- [ ] Recovery duration and any data loss window recorded.
- [ ] Test result and next test date recorded without credentials.
