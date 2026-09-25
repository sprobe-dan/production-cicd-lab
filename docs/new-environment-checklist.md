# New environment checklist

Use [the setup guide](vps-cicd-setup.md) for commands and verification, [backup and restore](backup-restore.md) for recovery tests, and the [deployment](deployment.md), [rollback](rollback.md), and [incident](incident-runbook.md) runbooks for operation. The current workflows support exact GitHub Environment names `staging` and `production`; a third name needs workflow and script changes.

- [ ] VPS created and region/size recorded.
- [ ] SSH host identity independently verified.
- [ ] `dan` administrator created; `sudo` verified.
- [ ] `deploy` user created with dedicated public keys.
- [ ] Both new logins verified in a second session.
- [ ] SSH password and root login disabled only after successful tests.
- [ ] SSH configuration validated and firewall enabled with SSH allowed.
- [ ] Docker Engine and Compose plugin installed; `deploy` Docker access verified.
- [ ] Nginx installed; two sites validated and external DNS/HTTPS planned.
- [ ] `/opt/production-cicd-lab` created with protected ownership.
- [ ] Separate protected environment files created with unique passwords.
- [ ] Checked-in staging/production Compose files and scripts installed with LF line endings.
- [ ] Public GHCR pull tested or private GHCR credentials configured.
- [ ] GitHub `staging` and `production` Environments created.
- [ ] Environment variables configured with exact workflow names.
- [ ] Environment SSH-key and complete verified known-hosts secrets configured.
- [ ] Production reviewer and deployment branch protection rules verified.
- [ ] First immutable SHA image published by `CI`.
- [ ] First staging deployment completed.
- [ ] Same SHA production deployment completed after approval.
- [ ] Alembic migration completed in each environment.
- [ ] Internal `/health` verified.
- [ ] Internal and external `/ready` verified.
- [ ] Public staging and production endpoints verified through Nginx.
- [ ] App containers, loopback port bindings, and deployed SHA confirmed.
- [ ] Second release deployed, rollback tested, and previous SHA verified.
- [ ] Intended latest image restored and verified.
- [ ] Separate database backups created and copied off-server.
- [ ] Database restore tested on an isolated host and result recorded.
- [ ] Deployment, rollback, incident, and backup runbooks reviewed.

## Non-secret environment record

~~~text
Environment name:
Server provider:
Server region:
Server IP or hostname:
Domain:
Internal application port:
GitHub Environment:
Compose project:
Application container:
Database container:
Created date:
Last restore test:
~~~

Do not record passwords, tokens, private keys, or complete environment-file contents here.
