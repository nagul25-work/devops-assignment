# devops-assignment

A containerised Node.js web application deployed to AWS via a fully automated CI/CD pipeline.

## Stack

- **App**: Node.js + Express
- **Container**: Docker (multi-stage build)
- **Registry**: Amazon ECR
- **Infrastructure**: Terraform (IaC)
- **Server**: AWS EC2 (t3.micro) + Nginx reverse proxy
- **CI/CD**: GitHub Actions

## Pipeline stages

1. **Test** — Jest unit tests with coverage report archived as artifact
2. **Build** — Docker image built and tagged with commit SHA
3. **Push** — Image pushed to Amazon ECR
4. **Deploy** — SSH into EC2, pull image, run container, reload Nginx, health check

## Rollback strategy

Every deployment tags the Docker image with the full Git commit SHA (e.g. `abc1234...`) in addition to `latest`. This means every previously deployed version is preserved in ECR and can be redeployed at any time.

### How to roll back

**Step 1 — Identify the last stable commit SHA**

Check the GitHub Actions run history or ECR image list:
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

### Preventing bad deployments

The pipeline includes a health check step after every deploy that hits `/health` and expects a `200` response. If the health check fails, the pipeline run is marked as failed — making the bad deployment immediately visible.

For a more automated rollback, revert the commit on `main` and push — the pipeline will automatically rebuild and redeploy the last working version:
```bash
git revert HEAD
git push origin main
```
