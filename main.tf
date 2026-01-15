variable "prj_prefix" {}
variable "region_site" {}
variable "region_acm" {}
variable "region_lambda_edge" {}
variable "route53_zone_id" {}
variable "domain_static_site" {}
variable "s3_static_site_force_destroy" {
  description = "S3 bucket force_destroy control. If true, it can be deleted even if objects exist"
  type        = bool
  default     = false
}
variable "enable_edge_lambda" {
  description = "Enable Lambda@Edge function for CloudFront distribution"
  type        = bool
  default     = false
}

provider "aws" {
  region = var.region_site
  alias  = "site"
}

provider "aws" {
  region = var.region_acm
  alias  = "acm"
}

provider "aws" {
  region = var.region_lambda_edge
  alias  = "lambda_edge"
}

#terraform {
#  backend "s3" {
#  }
#  required_providers {
#    aws = {
#      source  = "hashicorp/aws"
#      version = "= 5.94.1"
#    }
#  }
#}

locals {
  fqdn = {
    static_site = var.domain_static_site
  }
  bucket = {
    static_site = local.fqdn.static_site
  }
}

### S3 for cloudfront logs
#resource "aws_s3_bucket" "accesslog_static_site" {
#  provider      = aws.site
#  bucket        = "${local.fqdn.static_site}-accesslog"
#  force_destroy = true # Set true, destroy bucket with objects
#  acl           = "log-delivery-write"
#
#  tags = {
#    Name      = join("-", [var.prj_prefix, "s3", "accesslog_static_site"])
#    ManagedBy = "terraform"
#  }
#}

# ACM and Route53
## ACM Certification
resource "aws_acm_certificate" "static_site" {
  provider          = aws.acm
  domain_name       = local.fqdn.static_site
  validation_method = "DNS"

  tags = {
    Name      = join("-", [var.prj_prefix, "acm_static_site"])
    ManagedBy = "terraform"
  }
}
## CNAME Record
resource "aws_route53_record" "static_site_acm_c" {
  for_each = {
    for d in aws_acm_certificate.static_site.domain_validation_options : d.domain_name => {
      name   = d.resource_record_name
      record = d.resource_record_value
      type   = d.resource_record_type
    }
  }
  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 172800
  records         = [each.value.record]
  allow_overwrite = true
}
## Related ACM Certification and CNAME record
resource "aws_acm_certificate_validation" "static_site" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.static_site.arn
  validation_record_fqdns = [for record in aws_route53_record.static_site_acm_c : record.fqdn]
}
## A record
resource "aws_route53_record" "static_site_cdn_a" {
  zone_id = var.route53_zone_id
  name    = local.fqdn.static_site
  type    = "A"
  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.static_site.domain_name
    zone_id                = aws_cloudfront_distribution.static_site.hosted_zone_id
  }
}

# Lambda@Edge
## Create IAM Role and Policy
resource "aws_iam_role" "lambda_edge_role" {
  name = "${var.prj_prefix}-lambda-edge-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy" "lambda_edge_policy" {
  name = "${var.prj_prefix}-lambda-edge-policy"
  role = aws_iam_role.lambda_edge_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

## Lambda@Edge Function
resource "aws_lambda_function" "lambda_edge" {
  provider      = aws.lambda_edge
  function_name = join("-", [var.prj_prefix, "lambda_edge", "viewer_request"])
  role          = aws_iam_role.lambda_edge_role.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"

  # Put zip file to dist directory
  filename         = "${path.module}/functions/dist/lambda_edge_viewer_request.zip"
  source_code_hash = filebase64sha256("${path.module}/functions/dist/lambda_edge_viewer_request.zip")
  publish          = true
}

# CloudFront
## CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "static_site" {
  comment = "Origin Access Identity for s3 ${local.bucket.static_site} bucket"
}
## Cache Policy
data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "managed_caching_disabled" {
  name = "Managed-CachingDisabled"
}
### Refer: Elemental-MediaPackage for CORS
data "aws_cloudfront_cache_policy" "elemental_media_package" {
  name = "Managed-Elemental-MediaPackage"
}
## Origin Request Policy
### Refer: CORS-S3Origin for CORS
data "aws_cloudfront_origin_request_policy" "cors_s3origin" {
  name = "Managed-CORS-S3Origin"
}

## Distribution for Static Site
resource "aws_cloudfront_distribution" "static_site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name = "${local.bucket.static_site}.s3.${var.region_site}.amazonaws.com"
    origin_id   = "S3-${local.fqdn.static_site}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_site.cloudfront_access_identity_path
    }
  }

  # Alternate Domain Names (CNAMEs)
  aliases = [local.fqdn.static_site]

  # Config for SSL Certification
  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.static_site.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  retain_on_delete = false

  #logging_config {
  #  include_cookies = true
  #  bucket          = "${aws_s3_bucket.accesslog_static_site.id}.s3.amazonaws.com"
  #  prefix          = "log/static/prd/cf/"
  #}

  # For SPA to catch all request by /index.html
  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 404
    response_code      = 404
    response_page_path = "/errors/404.html"
  }

  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 403
    response_code      = 404
    response_page_path = "/errors/404.html"
  }

  default_cache_behavior {
    target_origin_id = "S3-${local.fqdn.static_site}"
    #viewer_protocol_policy = "allow-all"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    compress        = true
    cache_policy_id = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
    min_ttl         = 0
    default_ttl     = 3600
    max_ttl         = 86400

    # Related Lambda@Edge function (viewer-request event)
    dynamic "lambda_function_association" {
      for_each = var.enable_edge_lambda ? [aws_lambda_function.lambda_edge] : []
      content {
        event_type   = "viewer-request"
        lambda_arn   = lambda_function_association.value.qualified_arn
        include_body = false
      }
    }

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# S3 for Static Site
## Bucket Policy
data "aws_iam_policy_document" "s3_policy_static_site" {
  statement {
    #sid     = "PublicRead"
    sid     = "AllowCloudFrontAccess"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      #aws_s3_bucket.static_site.arn,
      "${aws_s3_bucket.static_site.arn}/*"
    ]

    # Accept to access from CloudFront only
    principals {
      identifiers = [aws_cloudfront_origin_access_identity.static_site.iam_arn]
      type        = "AWS"
    }

    ## Accept to access from All
    #principals {
    #  identifiers = ["*"]
    #  type        = "*"
    #}
  }
}
### Related S3 Bucket Policy
resource "aws_s3_bucket_policy" "static_site" {
  provider = aws.site
  bucket   = aws_s3_bucket.static_site.id
  policy   = data.aws_iam_policy_document.s3_policy_static_site.json
}

## S3 Bucket
resource "aws_s3_bucket" "static_site" {
  provider      = aws.site
  bucket        = local.bucket.static_site
  force_destroy = var.s3_static_site_force_destroy

  #logging {
  #  target_bucket = aws_s3_bucket.accesslog_static_site.id
  #  target_prefix = "log/static/prd/s3/"
  #}

  lifecycle {
    ignore_changes = [
      cors_rule,
      server_side_encryption_configuration,
    ]
  }

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "static_site"])
    ManagedBy = "terraform"
  }
}
#resource "aws_s3_bucket_website_configuration" "static_site_website" {
#  provider = aws.site
#  bucket = aws_s3_bucket.static_site.id
#
#  index_document {
#    suffix = "index.html"
#  }
#
#  error_document {
#    key = "error.html"
#  }
#}


# S3 Public Access Block
# Accept to access from All
resource "aws_s3_bucket_public_access_block" "static_site" {
  provider                = aws.site
  bucket                  = aws_s3_bucket.static_site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
