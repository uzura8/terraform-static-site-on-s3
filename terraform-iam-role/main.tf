#variable "prj_prefix" {}
variable "region_default" {}
variable "aws_account_id" {}
variable "target_role_name" {}

terraform {
  backend "s3" {
  }
}

resource "aws_iam_role" "target_role" {
  name = var.target_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:user/admin-base-user"
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "for_static_site" {
  name_prefix = "terraform_for_static_site"
  path        = "/"
  description = "Pike Autogenerated policy from IAC"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "acm:AddTagsToCertificate",
          "acm:DeleteCertificate",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:ListTagsForCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:RequestCertificate"
        ],
        "Resource" : [
          //"arn:aws:acm:${var.region_default}:${var.aws_account_id}:*"
          "*"
        ]
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : [
          "cloudfront:CreateCloudFrontOriginAccessIdentity",
          "cloudfront:CreateDistribution",
          "cloudfront:DeleteCloudFrontOriginAccessIdentity",
          "cloudfront:DeleteDistribution",
          "cloudfront:GetCloudFrontOriginAccessIdentity",
          "cloudfront:GetCachePolicy",
          "cloudfront:GetDistribution",
          "cloudfront:ListCachePolicies",
          "cloudfront:ListTagsForResource",
          "cloudfront:UpdateDistribution",
          "cloudfront:TagResource"
        ],
        "Resource" : [
          "arn:aws:cloudfront::${var.aws_account_id}:*"
        ]
      },
      {
        "Sid" : "VisualEditor2",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeAccountAttributes"
        ],
        "Resource" : [
          "arn:aws:ec2:${var.region_default}:${var.aws_account_id}:*"
        ]
      },
      {
        "Sid" : "VisualEditor3",
        "Effect" : "Allow",
        "Action" : [
          "route53:ChangeResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:GetChange",
          "route53:ListHostedZones"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "VisualEditor4",
        "Effect" : "Allow",
        "Action" : [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucketWebsite",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketLocation",
          "s3:GetBucketLogging",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketTagging",
          "s3:GetBucketVersioning",
          "s3:GetBucketWebsite",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:PutBucketAcl",
          "s3:PutObject",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketTagging",
          "s3:PutBucketWebsite",
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:DeleteBucketEncryption"
        ],
        "Resource" : [
          "arn:aws:s3:::*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "for_static_site_attachment" {
  role       = aws_iam_role.target_role.name
  policy_arn = aws_iam_policy.for_static_site.arn
}
