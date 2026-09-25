# Fresh VPS and CI/CD setup

This guide provisions one Ubuntu DigitalOcean Droplet for the checked-in GitHub Actions pipeline. Run commands only in the context named above each block. Start with [the checklist](new-environment-checklist.md); use [deployment](deployment.md), [rollback](rollback.md), [incident response](incident-runbook.md), and [backup and restore](backup-restore.md) during operation.

## Architecture and fixed repository values

`CI` publishes `ghcr.io/sprobe-dan/production-cicd-lab:<full 40-character SHA>` after a successful push to `main`. `Deploy staging` runs automatically after that CI run and can also be dispatched with `image_sha`. `Deploy production` is manual, takes `image_sha`, and uses the protected `production` GitHub Environment. `Rollback` is manual. The workflows upload Compose files and scripts over SSH to `deploy` on the Droplet. Docker runs separate FastAPI and PostgreSQL containers on separate Compose projects; Nginx routes public hostnames to loopback-only app ports. Alembic runs before the app starts. The image runs as the non-root `app` user.

| Environment | Compose file on server | Compose project | App container / loopback port | Database container | Environment file |
| --- | --- | --- | --- | --- | --- |
| staging | `compose.staging.yml` | `production-cicd-lab` | `production-cicd-lab-staging` / `8000` | `production-cicd-lab-postgres-staging` | `.env.staging` |
| production | `compose.production.yml` | `production-cicd-lab-production` | `production-cicd-lab-production` / `8001` | `production-cicd-lab-postgres-production` | `.env.production` |

Both database services are named `db`, both app services `api`, and each project has its own `postgres_data` volume. PostgreSQL has no published host port. `/health` says the application process is alive; `/ready` also checks database connectivity. Both should return HTTP 200, with `{"status":"healthy"}` and `{"status":"ready"}` respectively.

Staging and production share one VPS. Deployments may cause brief downtime. This is not highly available: the server is a single point of failure. Database backup and restore must be tested separately.

## Prerequisites and values to choose

Have access to the repository's GitHub Settings and Actions, a DigitalOcean account, a Git Bash terminal on Windows, and a second terminal for SSH testing. Use Ubuntu 24.04 LTS or another [Docker-supported Ubuntu release](https://docs.docker.com/engine/install/ubuntu/). The repository has no `.env.example`; its runtime files are `.env.staging` and `.env.production` on the server. The [example](../deploy/templates/environment.env.example) is only a reference.

Choose these values before running commands. Replace uppercase placeholders literally in command blocks; they are not shell variables.

| Placeholder | Meaning |
| --- | --- |
| `YOUR_DROPLET_IP` | New Droplet public IP |
| `YOUR_STAGING_DOMAIN`, `YOUR_PRODUCTION_DOMAIN` | Distinct DNS hostnames pointing to that IP |
| `YOUR_DOMAIN` | One of those hostnames when using a single-site template |
| `YOUR_GITHUB_USERNAME` | GitHub identity allowed to access the GHCR package |
| `YOUR_REPOSITORY` | Repository name; this pipeline expects `production-cicd-lab` in owner `sprobe-dan` |
| `YOUR_ENVIRONMENT` | `staging` or `production` |
| `YOUR_APP_PORT` | `8000` for staging, `8001` for production |
| `YOUR_FULL_SHA` | Full 40-character lowercase Git commit SHA of a published image |
| `YOUR_VERIFIED_HOST_FINGERPRINT` | ED25519 host key fingerprint read independently in the Droplet console |

The workflows and deploy scripts hard-code the GHCR owner/repository and server layout. If you fork or rename the repository, update those files consistently before using this guide; changing a table value alone will not retarget the pipeline. Choose the Droplet region/size with enough memory and disk for two databases and images, the SSH key identities, DNS names, a backup destination, and a real production reviewer.

## 1. Create the Droplet and verify SSH identity

**Local Windows, Git Bash:** create a password-protected administrator key and separate CI deployment keys. Keep private keys local; only the public `.pub` files go to the server. For Actions, copy each private key into its matching GitHub Environment secret through the web interface later.

~~~bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/production_cicd_lab_admin -C "production-cicd-lab admin"
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/production_cicd_lab_staging -C "production-cicd-lab staging"
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/production_cicd_lab_production -C "production-cicd-lab production"
~~~

Actions runs unattended, so press Enter twice for an empty passphrase when generating the two deployment keys. Protect those private keys as GitHub Environment secrets and restrict who may administer those environments. Give the administrator key a strong passphrase.

**DigitalOcean web interface:** add the administrator public key to your account, create an Ubuntu Droplet with that SSH key, record its IP and region, and point the two DNS records at it. Keep the DigitalOcean recovery console available during hardening. Record the Droplet's host fingerprint from its trusted console, not from an unverified network scan:

**Ubuntu VPS, trusted DigitalOcean console as root:**

~~~bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
~~~

**Local Windows, Git Bash:** scan the host's public key, compare its printed fingerprint with the console's `SHA256:...` value, then add the verified **entire** hashed line to local known hosts. Stop if they differ. A host-key change later requires independent investigation; never turn off strict host-key checking or blindly replace a host key.

~~~bash
ssh-keyscan -H -t ed25519 YOUR_DROPLET_IP > /tmp/production-cicd-lab-hostkey
ssh-keygen -lf /tmp/production-cicd-lab-hostkey
cat /tmp/production-cicd-lab-hostkey >> ~/.ssh/known_hosts
ssh -o StrictHostKeyChecking=yes -i ~/.ssh/production_cicd_lab_admin root@YOUR_DROPLET_IP
~~~

The fingerprint must match `YOUR_VERIFIED_HOST_FINGERPRINT`. The final command is the initial root connection; it should open a shell without a host-key prompt. If DigitalOcean did not install your key, recover through its console.

## 2. Update Ubuntu and create accounts

**Ubuntu VPS as root:** update packages. During `openssh-server` upgrades, if prompted about a locally changed `sshd_config`, keep the currently installed local version, inspect the maintainer version and merge intended changes later. Keep this SSH session open. Do not accept a replacement configuration without checking whether your login still works.

~~~bash
apt update
apt full-upgrade
apt install -y sudo ufw nginx ca-certificates curl gnupg openssl file
adduser dan
usermod -aG sudo dan
adduser --disabled-password --gecos "" deploy
install -d -m 700 -o dan -g dan /home/dan/.ssh
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
touch /home/dan/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown dan:dan /home/dan/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/dan/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
~~~

Set a strong password for `dan` when `adduser` asks; it supports `sudo` even though SSH password login will be disabled. Keep `deploy` outside `sudo`. Its Docker access below is effectively root-equivalent; allow only its dedicated keys and protect its GitHub secrets.

**Local Windows, Git Bash:** append the three public keys to the intended users. These commands transfer public keys only. If rerun, check for duplicate lines.

~~~bash
cat ~/.ssh/production_cicd_lab_admin.pub | ssh -i ~/.ssh/production_cicd_lab_admin root@YOUR_DROPLET_IP 'cat >> /home/dan/.ssh/authorized_keys'
cat ~/.ssh/production_cicd_lab_staging.pub | ssh -i ~/.ssh/production_cicd_lab_admin root@YOUR_DROPLET_IP 'cat >> /home/deploy/.ssh/authorized_keys'
cat ~/.ssh/production_cicd_lab_production.pub | ssh -i ~/.ssh/production_cicd_lab_admin root@YOUR_DROPLET_IP 'cat >> /home/deploy/.ssh/authorized_keys'
~~~

**Local Windows, second Git Bash terminal:** test new logins *before* disabling anything. The administrator's `sudo -v` should accept the `dan` password. The deploy login should work without a password and `sudo -n true` should fail. Keep the original root session open.

~~~bash
ssh -t -o StrictHostKeyChecking=yes -i ~/.ssh/production_cicd_lab_admin dan@YOUR_DROPLET_IP 'sudo -v && id'
ssh -o StrictHostKeyChecking=yes -i ~/.ssh/production_cicd_lab_staging deploy@YOUR_DROPLET_IP 'id'
~~~

## 3. Harden SSH and enable the firewall

**Lockout warning:** keep the root and successful `dan` sessions open, and keep the DigitalOcean console available. Validate the SSH configuration before reload; test a fresh `dan` and `deploy` connection afterward. If either fails, repair through the still-open session or console.

**Ubuntu VPS as root:** use an SSH drop-in and verify the effective policy. An earlier drop-in can override later values, so inspect `sshd -T` and existing `sshd_config.d` files before relying on these settings.

~~~bash
install -m 600 /dev/null /etc/ssh/sshd_config.d/01-production-cicd-lab.conf
cat > /etc/ssh/sshd_config.d/01-production-cicd-lab.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
sshd -t
sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication) '
systemctl reload ssh
~~~

Expected effective values: `no`, `no`, `no`, `yes` in that order. If they differ, inspect include order and correct it before proceeding. **Local Windows, second Git Bash terminal:** repeat both new-user SSH tests above. Only after they succeed should you close the original root session.

**Firewall warning:** allow SSH before enabling UFW. If SSH uses a custom port, allow that port instead of `OpenSSH`. The application ports 8000/8001 stay bound to `127.0.0.1` and should not be opened publicly.

**Ubuntu VPS as dan:**

~~~bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
~~~

Expected: active firewall with SSH, HTTP, and HTTPS allowed. Apply equivalent rules to a DigitalOcean Cloud Firewall if you use one; retain SSH access from your administrative location.

## 4. Install Docker Engine and Compose

**Ubuntu VPS as dan:** follow [Docker's current official Ubuntu repository instructions](https://docs.docker.com/engine/install/ubuntu/) when versions or supported releases change. For a fresh supported Ubuntu host:

~~~bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
~~~

If a conflicting Ubuntu `docker.io`/`containerd` installation already exists, resolve it using Docker's official instructions before installing; do not remove packages blindly on a populated host. **Ubuntu VPS as dan:** grant Docker access only to `deploy` and verify in a new login:

~~~bash
sudo usermod -aG docker deploy
getent group docker
~~~

**Local Windows, Git Bash:** reconnect `deploy`, then run `docker info` and `docker compose version`. Both should succeed without `sudo`. Docker group membership grants broad host control, so do not treat `deploy` as a low-privilege operating-system account.

## 5. Prepare deployment files and GHCR

**Ubuntu VPS as dan:** create the exact directory used by scripts and workflows. `deploy` must be able to replace Compose files and scripts and atomically write release state files. Keep home and SSH files protected.

~~~bash
sudo install -d -m 750 -o deploy -g deploy /opt/production-cicd-lab
sudo ls -ld /opt/production-cicd-lab
~~~

Expected owner/group `deploy deploy` and mode `drwxr-x---`. The workflow uploads `deploy/compose.staging.yml`, `scripts/deploy.sh`, `scripts/smoke-test.sh`, `scripts/rollback.sh` during staging. Production uploads `deploy/compose.production.yml` and `scripts/deploy-production.sh`. The root path is `/opt/production-cicd-lab`. You can install initial copies before the first workflow:

**Local Windows, Git Bash, from the repository root:**

~~~bash
scp -i ~/.ssh/production_cicd_lab_staging -o StrictHostKeyChecking=yes deploy/compose.staging.yml deploy/compose.production.yml scripts/deploy.sh scripts/deploy-production.sh scripts/rollback.sh scripts/smoke-test.sh deploy@YOUR_DROPLET_IP:/opt/production-cicd-lab/
ssh -i ~/.ssh/production_cicd_lab_staging deploy@YOUR_DROPLET_IP 'chmod 640 /opt/production-cicd-lab/compose.*.yml; chmod 750 /opt/production-cicd-lab/*.sh; file /opt/production-cicd-lab/*.sh'
~~~

Git tracks `*.sh` with LF via `.gitattributes`. From Windows, preserve Unix LF endings: `file` should report shell scripts without CRLF; if a script fails with `bash\r`, repair the local line endings, re-upload, and verify before deployment.

**GHCR:** a public container package can be pulled anonymously. For a private package, create a classic GitHub personal access token with `read:packages` and access to the package, then authenticate once as `deploy`. Do not put the token in the environment files or type it on the command line. In the `deploy` shell, use `read -r -s GHCR_TOKEN` to enter it invisibly, then:

~~~bash
read -r -s -p 'GHCR token: ' GHCR_TOKEN; printf '\n'
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
unset GHCR_TOKEN
chmod 700 ~/.docker
chmod 600 ~/.docker/config.json
~~~

Docker's default config stores registry credentials in the deploy user's home; protect this file and use a credential helper when available. The CI publish job uses its own `GITHUB_TOKEN` and `packages: write` permission. Verify package visibility and that the repository is authorized to publish. **Current private-package limitation:** `Deploy production` runs `docker manifest inspect` on the GitHub runner without a GHCR login. A private image can fail this preflight even when `deploy` can pull it. Before choosing private visibility, add a runner-side read-only GHCR login to that workflow, grant its `GITHUB_TOKEN` package read access, and verify the package grants this repository Actions access. The documented workflow works directly with a public image. [GitHub's GHCR guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) covers package access.

**Environment-file overwrite warning:** create one unique strong database password per environment; replacing a password after PostgreSQL initializes will not automatically change its database account. Keep the file mode `600` and do not print or commit its contents. **Ubuntu VPS as deploy:** the following creates each file with a private password without displaying it. `openssl rand -hex 32` produces the required 64 lowercase hex characters. Replace `YOUR_FULL_SHA` with a published image SHA when it is available; the deployment script writes the selected image SHA before Compose starts.

~~~bash
umask 077
set -C
DB_PASSWORD="$(openssl rand -hex 32)"
printf 'DB_PASSWORD=%s\nAPP_IMAGE=ghcr.io/sprobe-dan/production-cicd-lab:YOUR_FULL_SHA\n' "$DB_PASSWORD" > /opt/production-cicd-lab/.env.staging
unset DB_PASSWORD
DB_PASSWORD="$(openssl rand -hex 32)"
printf 'DB_PASSWORD=%s\nAPP_IMAGE=ghcr.io/sprobe-dan/production-cicd-lab:YOUR_FULL_SHA\n' "$DB_PASSWORD" > /opt/production-cicd-lab/.env.production
unset DB_PASSWORD
set +C
chmod 600 /opt/production-cicd-lab/.env.staging /opt/production-cicd-lab/.env.production
stat -c '%a %U:%G %n' /opt/production-cicd-lab/.env.staging /opt/production-cicd-lab/.env.production
~~~

The expected file mode is `600 deploy:deploy`. Do not use this command to overwrite files that already contain deployed database credentials. The exact format is two lines, `DB_PASSWORD=<64 lowercase hex characters>` and `APP_IMAGE=ghcr.io/sprobe-dan/production-cicd-lab:<full SHA>`; use a different password per file. The Compose template is for future environments; the checked-in production and staging Compose files are the ones current workflows use.

## 6. Configure Nginx and optional HTTPS

**Ubuntu VPS as dan:** create two sites from [the template](../deploy/templates/nginx-site.conf), replacing `YOUR_DOMAIN` and `YOUR_APP_PORT` with staging hostname/8000 and production hostname/8001. Edit in the server console; do not paste an unexpanded placeholder into an enabled site. Nginx configuration is not automatically uploaded by workflows.

~~~bash
sudo install -m 644 /dev/null /etc/nginx/sites-available/production-cicd-lab-staging
sudo install -m 644 /dev/null /etc/nginx/sites-available/production-cicd-lab-production
sudo editor /etc/nginx/sites-available/production-cicd-lab-staging
sudo editor /etc/nginx/sites-available/production-cicd-lab-production
sudo ln -s /etc/nginx/sites-available/production-cicd-lab-staging /etc/nginx/sites-enabled/production-cicd-lab-staging
sudo ln -s /etc/nginx/sites-available/production-cicd-lab-production /etc/nginx/sites-enabled/production-cicd-lab-production
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl status nginx --no-pager
~~~

Expected `nginx -t`: syntax OK and test successful. Do not reload if validation fails. For public HTTPS, first point DNS records at the Droplet, then obtain certificates using your chosen ACME client and add TLS and HTTP-to-HTTPS redirects. Validate renewal and `nginx -t` before relying on HTTPS. Set GitHub URLs to the final `https://...` addresses. The template forwards `Host`, client address, and protocol headers; `/health` and `/ready` use the same proxy route.

## 7. Configure GitHub Environments

**GitHub web interface:** in repository `YOUR_REPOSITORY`, open **Settings → Environments**. Create exact environment names `staging` and `production`. Allow `main` for staging and production; require named reviewer approval for production and enable prevention of self-review where available. Staging should permit unattended deployment from successful CI on `main`. Restrict who can edit workflows and environments. GitHub plan and repository visibility can affect available protection rules; verify the approval gate actually holds a test production job before relying on it. See [GitHub environment protection rules](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

Create these **environment-scoped variables and secrets**, not repository-wide copies. Both environments point at the same Droplet but different external URLs and SSH keys. GitHub's built-in `GITHUB_TOKEN` is not a manually created secret.

| Environment | Variables (`vars`) | Secrets (`secrets`) |
| --- | --- | --- |
| `staging` | `STAGING_HOST=YOUR_DROPLET_IP`, `STAGING_USER=deploy`, `STAGING_URL=https://YOUR_STAGING_DOMAIN` | `STAGING_SSH_KEY`, `STAGING_KNOWN_HOSTS` |
| `production` | `PRODUCTION_HOST=YOUR_DROPLET_IP`, `PRODUCTION_USER=deploy`, `PRODUCTION_URL=https://YOUR_PRODUCTION_DOMAIN` | `PRODUCTION_SSH_KEY`, `PRODUCTION_KNOWN_HOSTS` |

**Local Windows, Git Bash:** use each deployment private key file as the corresponding `*_SSH_KEY` secret, preserving its complete multiline text, including header/footer and final newline. Never commit, email, or print it in logs. To obtain each `*_KNOWN_HOSTS` value, use the verified host-key procedure in section 1. Store the entire hashed `ssh-keyscan -H` output line, including the leading `|1|...` hostname hash, key type, and base64 public key. Copying only the key or fingerprint will fail strict checking. For this shared host, both secrets may contain the same verified line. If using hostnames instead of IPs in `*_HOST`, scan and verify each exact hostname used by SSH; a hashed IP line does not match a hostname.

Repository secrets are available broadly to workflows that request them. Environment secrets are available only to jobs naming that environment and, for protected production, only after approval. Do not place SSH keys in repository secrets as a shortcut. [GitHub's secrets guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) explains the scopes.

## 8. First release, verification, and rollback drill

**Database and image-retention warning:** normal deployment runs `alembic upgrade head` and changes database schema. Take a verified backup before migrations that could affect existing data. The deployment scripts also run `docker image prune --force`, which removes unused local images; keep published rollback images accessible in GHCR.

**GitHub web interface:** merge a reviewed change into `main`. `CI` must pass and publish `ghcr.io/sprobe-dan/production-cicd-lab:YOUR_FULL_SHA`. `Deploy staging` should run after that successful push and upload files. Check its log for image pull, database startup, Alembic upgrade, app readiness, and external readiness. Manual `Deploy staging` with `image_sha` is available when needed. After staging passes, run `Deploy production` with the **same full SHA** and approve the production Environment. Do not rebuild for promotion. A first run may require GHCR package visibility and DNS/HTTPS readiness before external checks can pass.

**Ubuntu VPS as deploy:** inspect containers, ports, exact image references, migrations, and state after deployment:

~~~bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker inspect --format='{{.Name}} {{.Config.Image}} {{.State.Health.Status}}' production-cicd-lab-staging production-cicd-lab-production
docker compose --project-name production-cicd-lab --env-file /opt/production-cicd-lab/.env.staging --file /opt/production-cicd-lab/compose.staging.yml run --rm --no-deps api alembic current
docker compose --project-name production-cicd-lab-production --env-file /opt/production-cicd-lab/.env.production --file /opt/production-cicd-lab/compose.production.yml run --rm --no-deps api alembic current
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8000/ready
curl --fail http://127.0.0.1:8001/health
curl --fail http://127.0.0.1:8001/ready
~~~

Expected: two healthy app containers and two healthy database containers; ports show `127.0.0.1:8000->8000/tcp` and `127.0.0.1:8001->8000/tcp`, not public bindings. Image references end in the intended SHA, and `alembic current` displays the repository head revision. Use public `https://YOUR_STAGING_DOMAIN/ready` and `https://YOUR_PRODUCTION_DOMAIN/ready` from a local browser or `curl`. Release state files are `.current-image.staging`, `.previous-image.staging`, `.current-image.production`, and `.previous-image.production` in `/opt/production-cicd-lab`.

**Rollback requires two releases.** The first deployment has no previous image. After a second, backward-compatible image has been published and deployed to an environment, note its SHA, run GitHub Actions **Rollback** for that environment, approve production if applicable, and verify `/ready` and `docker inspect` show the earlier SHA. Then use the normal `Deploy staging` or `Deploy production` workflow with the noted latest full SHA and verify it is restored. Follow [the rollback runbook](rollback.md). An application rollback does not reverse database migrations; make schema changes backward-compatible and take a verified backup before risky migrations.

## 9. Routine maintenance and troubleshooting

Review OS and Docker updates, disk and memory, Nginx and Docker service status, TLS renewal, GHCR credentials, GitHub Environment reviewers/secrets, off-server backups, restore tests, and release state. Before changing a database password or restoring a volume, use [the backup runbook](backup-restore.md). Coordinate maintenance because the two environments share the host.

| Symptom | Check |
| --- | --- |
| SSH host-key mismatch | Compare the new fingerprint through the trusted Droplet console; investigate before replacing any known-hosts value. Never disable strict checking. |
| SSH permission denied | Key pair, `deploy` authorized keys/modes, GitHub secret scope, `*_HOST` and `*_USER`. |
| Docker permission denied | Reconnect `deploy` after group change; `id` should show `docker`. |
| GHCR pull denied | Package visibility or deploy user's Docker login/token `read:packages` access. |
| `/health` fails | App status and logs via `docker ps` and `docker logs`. |
| `/health` passes but `/ready` fails | Database container health, logs, credentials, disk, and Compose project. |
| Internal checks pass, public checks fail | DNS, Nginx `nginx -t`, TLS, UFW and DigitalOcean firewall. |
| `bash\r` in script error | CRLF upload; restore LF and upload again. |
| Rollback reports no previous image | Deploy a second valid release first; never invent a state file. |

Use [incident response](incident-runbook.md) for live failures. **Destructive-operation warnings:** do not use `docker compose down -v`, `docker volume rm`, or broad prune commands during diagnosis. The checked-in deploy scripts do run `docker image prune --force` after deployment; keep needed rollback images in GHCR. Do not overwrite environment files or rotate host keys without a reviewed recovery plan. Database restore changes live state and must be rehearsed in a controlled environment.
