output "site_bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "site_url" {
  value = (
    var.enable_cloudfront
    ? "https://${aws_cloudfront_distribution.site[0].domain_name}"
    : "http://${aws_s3_bucket_website_configuration.site[0].website_endpoint}"
  )
}

output "custom_domain_url" {
  value = (var.enable_cloudfront && var.enable_custom_domain) ? "https://${var.site_domain_name}" : null
}

output "api_url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "pipeline_name" {
  value = aws_codepipeline.this.name
}
