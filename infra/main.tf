locals {
  tags = merge(var.tags, {
    NamePrefix = var.name_prefix
  })

  # AWS created two ARN service prefixes for Connections (historical: codestar-connections; newer: codeconnections).
  # The CodePipeline Source action may reference either.
  codestar_connection_arns = distinct([
    var.codestar_connection_arn,
    replace(var.codestar_connection_arn, "arn:aws:codeconnections:", "arn:aws:codestar-connections:"),
    replace(var.codestar_connection_arn, "arn:aws:codestar-connections:", "arn:aws:codeconnections:")
  ])
}

data "aws_caller_identity" "this" {}

# -----------------------------
# S3 Buckets
# -----------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name_prefix}-artifacts-${data.aws_caller_identity.this.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket" "site" {
  bucket        = "${var.name_prefix}-site-${data.aws_caller_identity.this.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# If CloudFront is disabled, you can use S3 static website hosting (public).
resource "aws_s3_bucket_website_configuration" "site" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "site_public_policy" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["${aws_s3_bucket.site.arn}/*"]
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "site_public" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# -----------------------------
# CloudFront (optional)
# -----------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  count                             = var.enable_cloudfront ? 1 : 0
  name                              = "${var.name_prefix}-oac"
  description                       = "OAC for S3 site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ACM certificate for custom domain (optional)
resource "aws_acm_certificate" "site" {
  count             = (var.enable_cloudfront && var.enable_custom_domain) ? 1 : 0
  domain_name       = var.site_domain_name
  validation_method = "DNS"
  tags              = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "site_cert_validation" {
  count   = (var.enable_cloudfront && var.enable_custom_domain) ? 1 : 0
  zone_id = var.route53_zone_id
  name    = tolist(aws_acm_certificate.site[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.site[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.site[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "site" {
  count                   = (var.enable_cloudfront && var.enable_custom_domain) ? 1 : 0
  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [aws_route53_record.site_cert_validation[0].fqdn]
}

resource "aws_cloudfront_distribution" "site" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} site"
  default_root_object = "index.html"

  aliases = (var.enable_custom_domain ? [var.site_domain_name] : [])

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac[0].id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "s3-site"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.enable_custom_domain ? aws_acm_certificate_validation.site[0].certificate_arn : null
    cloudfront_default_certificate = var.enable_custom_domain ? false : true
    ssl_support_method             = var.enable_custom_domain ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = local.tags

  depends_on = [
    aws_s3_bucket_public_access_block.site,
    aws_acm_certificate_validation.site
  ]
}

resource "aws_s3_bucket_policy" "site_oac_policy" {
  count  = var.enable_cloudfront ? 1 : 0
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.site.arn}/*"]
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site[0].arn
          }
        }
      }
    ]
  })
}

resource "aws_route53_record" "site_alias" {
  count   = (var.enable_cloudfront && var.enable_custom_domain) ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.site_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site[0].domain_name
    zone_id                = aws_cloudfront_distribution.site[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------
# DynamoDB
# -----------------------------
resource "aws_dynamodb_table" "notes" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "noteId"

  attribute {
    name = "noteId"
    type = "S"
  }

  tags = local.tags
}

# -----------------------------
# IAM for Lambda
# -----------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_ddb" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.notes.arn]
  }
}

resource "aws_iam_policy" "lambda_ddb" {
  name   = "${var.name_prefix}-lambda-ddb"
  policy = data.aws_iam_policy_document.lambda_ddb.json
}

resource "aws_iam_role_policy_attachment" "lambda_ddb" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_ddb.arn
}

# -----------------------------
# Lambda
# -----------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.name_prefix}-api"
  role          = aws_iam_role.lambda.arn
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.notes.name
    }
  }

  tags = local.tags
}

# -----------------------------
# Cognito (Auth)
# -----------------------------
resource "aws_cognito_user_pool" "this" {
  name = "${var.name_prefix}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.name_prefix}-app-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "this" {
  count        = var.enable_cognito_hosted_ui_domain ? 1 : 0
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# -----------------------------
# API Gateway HTTP API + JWT Authorizer
# -----------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.name_prefix}-http-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_headers = ["*"]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
  }
  tags = local.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  name             = "${var.name_prefix}-jwt"
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

# Route all requests to Lambda (matches /notes and /notes/{proxy+})
resource "aws_apigatewayv2_route" "notes" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /notes"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "notes_proxy" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /notes/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# -----------------------------
# CodeBuild + CodePipeline
# -----------------------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.name_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "codebuild_basic" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

data "aws_iam_policy_document" "codebuild_extra" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObject"
    ]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "codebuild_extra" {
  name   = "${var.name_prefix}-codebuild-extra"
  policy = data.aws_iam_policy_document.codebuild_extra.json
}

resource "aws_iam_role_policy_attachment" "codebuild_extra" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild_extra.arn
}

resource "aws_codebuild_project" "frontend" {
  name         = "${var.name_prefix}-frontend-build"
  description  = "Builds frontend and deploys to S3 (and invalidates CloudFront)"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false

    environment_variable {
      name  = "SITE_BUCKET_NAME"
      value = aws_s3_bucket.site.bucket
    }

    environment_variable {
      name  = "CLOUDFRONT_DISTRIBUTION_ID"
      value = var.enable_cloudfront ? aws_cloudfront_distribution.site[0].id : "none"
    }

    environment_variable {
      name  = "FRONTEND_APP_DIR"
      value = var.frontend_app_dir
    }

    environment_variable {
      name  = "FRONTEND_BUILD_COMMAND"
      value = var.frontend_build_command
    }

    environment_variable {
      name  = "FRONTEND_BUILD_OUTPUT_DIR"
      value = var.frontend_build_output_dir
    }

    # Optional: pass backend values to the build (useful if your build injects .env files)
    environment_variable {
      name  = "API_BASE_URL"
      value = aws_apigatewayv2_api.http.api_endpoint
    }

    environment_variable {
      name  = "COGNITO_USER_POOL_ID"
      value = aws_cognito_user_pool.this.id
    }

    environment_variable {
      name  = "COGNITO_USER_POOL_CLIENT_ID"
      value = aws_cognito_user_pool_client.this.id
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${var.name_prefix}-frontend"
      stream_name = "build"
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
  tags               = local.tags
}

// NOTE: Avoid attaching broad managed policies (and some names vary).
// Rely on the custom inline policies below for least-privilege.

# Allow the pipeline service role to use the GitHub CodeStar Connection.
# NOTE: We allow both arn:aws:codestar-connections:... and arn:aws:codeconnections:... because the console/UI and
# the CodePipeline execution error messages can show either prefix.
data "aws_iam_policy_document" "codepipeline_use_connection" {
  statement {
    sid     = "UseCodeStarConnection"
    effect  = "Allow"
    actions = [
      "codestar-connections:UseConnection",
      "codestar-connections:GetConnection"
    ]
    resources = local.codestar_connection_arns
  }
}

resource "aws_iam_policy" "codepipeline_use_connection" {
  name   = "${var.name_prefix}-codepipeline-use-connection"
  policy = data.aws_iam_policy_document.codepipeline_use_connection.json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "codepipeline_use_connection" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = aws_iam_policy.codepipeline_use_connection.arn
}

resource "aws_codepipeline" "this" {
  name     = "${var.name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "BuildAndDeploy"

    action {
      name             = "BuildAndDeploy"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.frontend.name
      }
    }
  }

  tags = local.tags
}
