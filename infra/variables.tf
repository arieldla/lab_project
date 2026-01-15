variable "aws_region" {
  description = "AWS region for the lab (recommend us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "dlagroup-serverless-webapp"
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default = {
    Project = "lab"
    Owner   = "Ariel"
    System  = "DLAGROUP"
    Env     = "Lab"
  }
}

# -----------------------------
# Frontend + CI/CD
# -----------------------------
variable "github_owner" {
  description = "GitHub org/user that owns the repo."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_branch" {
  description = "Branch to build/deploy."
  type        = string
  default     = "main"
}

variable "codestar_connection_arn" {
  description = "ARN of an AWS CodeStar Connection to GitHub (create/authorize in console)."
  type        = string
}

variable "frontend_app_dir" {
  description = "Relative directory (within the repo) that contains your frontend app (package.json)."
  type        = string
  default     = "app"
}

variable "frontend_build_command" {
  description = "Command CodeBuild runs to build the frontend."
  type        = string
  default     = "npm ci && npm run build"
}

variable "frontend_build_output_dir" {
  description = "Directory produced by the build (React typically 'build', Vite often 'dist')."
  type        = string
  default     = "dist"
}

variable "enable_cloudfront" {
  description = "If true, serve the site via CloudFront; else use S3 website endpoint."
  type        = bool
  default     = true
}

# Optional custom domain (Route53 + ACM)
variable "enable_custom_domain" {
  description = "If true, creates ACM cert (DNS validation) and Route53 record for CloudFront."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (required if enable_custom_domain=true)."
  type        = string
  default     = ""
}

variable "site_domain_name" {
  description = "Custom domain name (e.g., app.dlagroupinc.com) (required if enable_custom_domain=true)."
  type        = string
  default     = ""
}

# -----------------------------
# Backend
# -----------------------------
variable "dynamodb_table_name" {
  description = "DynamoDB table for notes/items."
  type        = string
  default     = "dlagroup-notes"
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler."
  type        = string
  default     = "app.handler"
}

variable "enable_cognito_hosted_ui_domain" {
  description = "If true, creates a Cognito hosted UI domain prefix (for OAuth flows)."
  type        = bool
  default     = false
}

variable "cognito_domain_prefix" {
  description = "Cognito domain prefix (unique in region). Required if enable_cognito_hosted_ui_domain=true."
  type        = string
  default     = ""
}
