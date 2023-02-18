provider "aws" {
    alias  = "us-east-1"
    region = "us-east-1"
}

data "aws_route53_zone" "selected" {
    name         = "${var.public_hosted_zone_name}."
    private_zone = false
}

resource "aws_s3_bucket" "website_bucket" {
    bucket = "${var.public_hosted_zone_name}"
    tags = var.tags
}

resource "aws_s3_bucket_acl" "website_bucket_acl" {
    bucket = aws_s3_bucket.website_bucket.id
    acl = "private"
}

resource "aws_s3_bucket_public_access_block" "website_bucket_public_access_block" {
    bucket = aws_s3_bucket.website_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    restrict_public_buckets = true
    ignore_public_acls      = true
}

resource "aws_s3_bucket_website_configuration" "website_configuration" {
    bucket = aws_s3_bucket.website_bucket.bucket
    index_document {
        suffix = var.index_document_suffix 
    }
    error_document {
        key = var.error_document_key
    }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = <<EOF
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Sid":"PublicReadForGetBucketObjects",
            "Effect":"Allow",
            "Principal": {
                "AWS":[
                    "${aws_cloudfront_origin_access_identity.website_oai.iam_arn}"
                ]
            },
            "Action":["s3:GetObject"],
            "Resource":[
                "arn:aws:s3:::${var.public_hosted_zone_name}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_cloudfront_origin_access_identity" "website_oai" {
    comment = "OAI for ${var.public_hosted_zone_name}"
}

resource "aws_cloudfront_distribution" "website_root_distribution" {
    origin {
        domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
        origin_id   = var.public_hosted_zone_name
        s3_origin_config {
            origin_access_identity = aws_cloudfront_origin_access_identity.website_oai.cloudfront_access_identity_path
        }
    }
    enabled             = true
    default_root_object = var.index_document_suffix
    aliases = [
        var.public_hosted_zone_name,
        "www.${var.public_hosted_zone_name}"
    ]

    default_cache_behavior {
        viewer_protocol_policy = "redirect-to-https"
        compress               = true
        allowed_methods        = ["GET", "HEAD"]
        cached_methods         = ["GET", "HEAD"]
        target_origin_id       = "${var.public_hosted_zone_name}"
        min_ttl                = 0
        default_ttl            = 86400
        max_ttl                = 31536000

        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
    }

    custom_error_response {
        error_code = "403"
        response_code = "200"
        response_page_path = "/${var.error_document_key}"
        error_caching_min_ttl = 10
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    viewer_certificate {
        acm_certificate_arn = module.acm.acm_certificate_arn
        ssl_support_method  = "sni-only"
        minimum_protocol_version = "TLSv1.2_2021"
    }
    tags = var.tags
}

# https://github.com/terraform-aws-modules/terraform-aws-acm
# CloudFront supports US East (N. Virginia) Region only.
module "acm" {
    source  = "terraform-aws-modules/acm/aws"
    version = "~> 4.0"

    providers = {
        aws = aws.us-east-1
    }

    domain_name  = var.public_hosted_zone_name
    zone_id      = data.aws_route53_zone.selected.zone_id

    subject_alternative_names = [
        "www.${var.public_hosted_zone_name}",
    ]

    wait_for_validation = true

    tags = var.tags
}

