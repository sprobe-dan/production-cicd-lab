# Production CI/CD Lab

[![CI](https://github.com/sprobe-dan/production-cicd-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/sprobe-dan/production-cicd-lab/actions/workflows/ci.yml)

A hands-on project for learning how to build a production-ready CI/CD pipeline using GitHub Actions, Python, Docker, and PostgreSQL.

## Current Pipeline

The current workflow runs when:

- Code is pushed to `main`
- It is manually triggered using `workflow_dispatch`

The workflow:

1. Creates a temporary Ubuntu runner
2. Checks out the repository
3. Executes diagnostic commands
4. Reports whether the job passed or failed

```text
Push or manual trigger
→ Create runner
→ Check out repository
→ Execute steps
→ Report success or failure