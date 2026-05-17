# devops-assignment

A containerised Node.js web application deployed to AWS via a fully automated CI/CD pipeline.

## Stack

| Layer | Technology |
|---|---|
| App | Node.js + Express |
| Container | Docker (multi-stage build) |
| Registry | Amazon ECR |
| Infrastructure | Terraform (IaC) |
| Server | AWS EC2 (t3.micro) |
| Reverse Proxy | Nginx |
| CI/CD | GitHub Actions |

## Pipeline Stages

The pipeline triggers on every push to `main` and runs three jobs in sequence. A failure at any stage halts the rest.

### 1. Test
- Installs dependencies with `npm ci`
- Runs Jest unit tests with `--coverage`
- Uploads the coverage report as a downloadable build artifact

### 2. Build
- Authenticates with Amazon ECR
- Builds a multi-stage Docker image
- Tags the image with the full Git commit SHA and `latest`
- Pushes both tags to ECR
- Archives the image digest (sha256) to S3.

### 3. Deploy
- Copies `nginx/nginx.conf` to the EC2 instance via SCP
- Reloads Nginx with the updated config (`nginx -t` validates before reload)
- Pulls the SHA-tagged image from ECR
- Stops and removes the old container, starts the new one
- Runs a health check against `/health` — pipeline fails if it does not return 200
- Sends a Slack notification with pass/fail status

## Infrastructure (Terraform)

All cloud resources are provisioned with Terraform.

Resources created:

- **ECR repository** — private container registry with `scan_on_push` enabled
- **EC2 instance** — Ubuntu 22.04, t3.micro, bootstrapped with Docker, Nginx, and AWS CLI via `user_data`
- **IAM role** — attached to EC2 with `AmazonEC2ContainerRegistryReadOnly`, allowing the instance to pull from ECR without hardcoded credentials
- **Security group** — allows inbound SSH (22) and HTTP (80), unrestricted outbound

Terraform state is stored remotely in S3 with locking enabled, so state is shared and consistent across machines.

### Provision infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Docker

The Dockerfile uses a multi-stage build:

- **Stage 1 (`deps`)** — installs only production dependencies via `npm ci --only=production`
- **Stage 2 (`runner`)** — copies the built artifacts, sets file ownership, and switches to a non-root user (`appuser`) before starting the process

## Nginx

Nginx runs directly on the EC2 host as a reverse proxy, listening on port 80 and forwarding traffic to the app container on port 3000.

## Rollback Strategy

Every deployment tags the Docker image with the full Git commit SHA (e.g. `abc1234...`) in addition to `latest`. This means every previously deployed version is preserved in ECR and can be redeployed at any time.

### Manual rollback

**Step 1 — Identify the last stable commit SHA**

Check the GitHub Actions run history or list images in ECR:

```bash
aws ecr list-images --repository-name devops-assignment --region ap-south-1
```

**Step 2 — SSH into the EC2 instance**

```bash
ssh -i devops-assignment-key.pem ubuntu@<ec2-public-ip>
```

**Step 3 — Stop the current container and redeploy the previous image**

```bash
docker stop app
docker rm app
docker run -d --name app -p 3000:3000 --restart unless-stopped \
  <ecr-repo-url>/devops-assignment:<previous-commit-sha>
```

**Step 4 — Verify**

```bash
curl http://localhost/health
```

### Automated rollback via git revert

Revert the bad commit on `main` and push — the pipeline will automatically rebuild and redeploy the last working version:

```bash
git revert HEAD
git push origin main
```

### Preventing bad deployments

The pipeline includes a health check step after every deploy that hits `/health` and expects a `200` response. If the health check fails, the pipeline run is marked as failed and a Slack notification is sent — making the bad deployment immediately visible before it can cause further damage.

## Secrets

The following secrets must be configured in GitHub repository settings before the pipeline can run:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `EC2_HOST` | Public IP of the EC2 instance |
| `EC2_SSH_KEY` | Private key for SSH access (PEM format) |
| `SLACK_WEBHOOK_URL` | Incoming webhook URL for deploy notifications |
