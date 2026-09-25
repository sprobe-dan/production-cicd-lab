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
