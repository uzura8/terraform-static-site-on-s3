variable "prj_prefix" {}
variable "region_site" {}
variable "region_acm" {}
variable "route53_zone_id" {}
variable "domain_static_site" {}

provider "aws" {
  region = var.region_site
  alias  = "site"
}

provider "aws" {
  region = var.region_acm
  alias  = "acm"
}

locals {
  fqdn = {
    static_site = var.domain_static_site
  }
  bucket = {
    static_site = local.fqdn.static_site
  }
}

## S3 for cloudfront logs
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

resource "aws_acm_certificate" "static_site" {
  provider          = aws.acm
  domain_name       = local.fqdn.static_site
  validation_method = "DNS"

  tags = {
    Name      = join("-", [var.prj_prefix, "acm_static_site"])
    ManagedBy = "terraform"
  }
}

# CNAME Record
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

# Create CloudFront OAI
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

## Distribution
resource "aws_cloudfront_distribution" "static_site" {
  origin {
    domain_name = "${local.bucket.static_site}.s3.${var.region_site}.amazonaws.com"
    origin_id   = "S3-${local.fqdn.static_site}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_site.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${local.fqdn.static_site}"
    #viewer_protocol_policy = "allow-all"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}


## Create IAM poliocy document
## Allow from all
#data "aws_iam_policy_document" "s3_policy_static_site" {
#  statement {
#    sid     = "PublicRead"
#    effect  = "Allow"
#    actions = ["s3:GetObject"]
#    resources = [
#      aws_s3_bucket.static_site.arn,
#      "${aws_s3_bucket.static_site.arn}/*"
#    ]
#
#    ## Accept to access from CloudFront only
#    #principals {
#    #  identifiers = [aws_cloudfront_origin_access_identity.static_site.iam_arn]
#    #  type        = "AWS"
#    #}
#
#    # Accept to access from All
#    principals {
#      identifiers = ["*"]
#      type        = "*"
#    }
#  }
#}
# Allow from only CloudFront
data "aws_iam_policy_document" "s3_policy_static_site" {
  statement {
    sid     = "AllowCloudFrontAccess"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.static_site.arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.static_site.iam_arn]
    }
  }

}

# Related policy to bucket
resource "aws_s3_bucket_policy" "static_site" {
  provider = aws.site
  bucket   = aws_s3_bucket.static_site.id
  policy   = data.aws_iam_policy_document.s3_policy_static_site.json
}

## S3 for Static Website Hosting
resource "aws_s3_bucket" "static_site" {
  provider      = aws.site
  bucket        = local.bucket.static_site
  force_destroy = true # Set true, destroy bucket with objects

  acl = "private" # Accept to access from CloudFront only
  #acl = "public-read" # Accept to access to S3 Bucket from All

  #logging {
  #  target_bucket = aws_s3_bucket.accesslog_static_site.id
  #  target_prefix = "log/static/prd/s3/"
  #}

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "static_site"])
    ManagedBy = "terraform"
  }
}


## S3 Public Access Block
## Accept to access from All
#resource "aws_s3_bucket_public_access_block" "static_site" {
#  provider                = aws.site
#  bucket                  = aws_s3_bucket.static_site.id
#  block_public_acls       = false
#  block_public_policy     = false
#  ignore_public_acls      = false
#  restrict_public_buckets = false
#}
# Deny to access from All
resource "aws_s3_bucket_public_access_block" "static_site" {
  provider                = aws.site
  bucket                  = aws_s3_bucket.static_site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


