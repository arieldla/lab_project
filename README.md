# DLAGROUP — Serverless Web App + CI/CD (Terraform)

This build combines:
- **Serverless backend**: Cognito (Auth) + API Gateway (HTTP API) + Lambda + DynamoDB + IAM
- **Frontend hosting + CI/CD**: S3 + CloudFront + CodePipeline + CodeBuild (pulls from GitHub)

It’s designed to be **weekend‑lab friendly** (managed/serverless, minimal always‑on compute).

---

## Architecture (high level)

User → CloudFront → S3 (static React build)
             ↘
              API Gateway (HTTP API) → Lambda → DynamoDB
                       ↑
                    Cognito JWT Authorizer

---

## Prereqs

1. Terraform >= 1.5
2. AWS credentials for the target account (us-east-1 recommended)
3. A GitHub repo that contains a React app (or any static web app that builds to a folder, usually `build/` or `dist/`)

This repo expects your frontend app to be in **`app/`** (the folder that contains `package.json`).
If you prefer a different folder, set `frontend_app_dir` in `terraform.tfvars`.

### One-time manual step (GitHub → AWS connection)
AWS CodePipeline uses **CodeStar Connections** to connect to GitHub. Creating the connection requires a browser click to authorize GitHub.

You will:
- Create the connection once in AWS Console
- Copy its ARN into `terraform.tfvars`

---

## Quick start

### 1) Copy the tfvars template
```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

### 2) Fill in terraform.tfvars
Set:
- `github_owner`, `github_repo`, `github_branch`
- `codestar_connection_arn` (from the Console step below)
- Optional: `site_domain_name` and Route53 zone if you want a custom domain

### 3) Create CodeStar connection (console)
In AWS Console (us-east-1):
- Developer Tools → **Connections**
- Create connection → **GitHub**
- Complete authorization
- Copy **Connection ARN** into `terraform.tfvars` as `codestar_connection_arn`

> Terraform can create the connection resource, but authorization still requires the console step.
> To reduce friction, this project expects you to paste the ARN.

### 4) Deploy
```bash
cd infra
terraform init
terraform apply
```

### 5) Push to GitHub to trigger pipeline
After apply:
- Commit/push to your GitHub repo branch
- Pipeline runs: build → upload → CloudFront invalidation

---

## Outputs you’ll use
Terraform prints:
- CloudFront URL (site)
- API URL
- Cognito User Pool ID + Client ID

Use these in your frontend `.env`:

For **Vite**, env vars must start with `VITE_`:
- `VITE_API_BASE_URL=<api_url>`
- `VITE_COGNITO_USER_POOL_ID=<user_pool_id>`
- `VITE_COGNITO_USER_POOL_CLIENT_ID=<user_pool_client_id>`
- `VITE_AWS_REGION=us-east-1`

(Your exact env names depend on your frontend code.)

---

## Teardown
```bash
cd infra
terraform destroy
```

S3 buckets are set to `force_destroy = true` so destroy removes objects too.

---

## Cost notes (lab-safe defaults)
- Lambda/DynamoDB/API Gateway: pay-per-use; very cheap at low traffic.
- CloudFront: small cost at low usage (still usually pennies/dollars).
- CodeBuild: billed per build minute (small for tiny repos).

If you want *zero CloudFront cost*, set `enable_cloudfront = false` (you’ll get S3 website hosting instead).

---

## Folder layout
- `app/` your frontend code (Vite/React, etc.)
- `infra/` Terraform for all AWS resources
- `infra/buildspec.yml` used by CodeBuild

