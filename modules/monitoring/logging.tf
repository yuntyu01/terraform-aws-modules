# S3 버킷
resource "aws_s3_bucket" "log_bucket" {
  bucket        = "${var.name}-log-archive-${var.region}"
  force_destroy = true
}

# IAM Role (Firehose -> S3)
resource "aws_iam_role" "firehose_role" {
  name = "${var.name}-firehose-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", 
    Statement = [{ 
        Action = "sts:AssumeRole", 
        Effect = "Allow", 
        Principal = { 
            Service = "firehose.amazonaws.com" 
        } 
    }]
  })
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "firehose-s3"
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17", 
    Statement = [{ 
        Effect = "Allow", 
        Action = ["s3:PutObject", "s3:GetBucketLocation"], 
        Resource = [aws_s3_bucket.log_bucket.arn, "${aws_s3_bucket.log_bucket.arn}/*"] 
    }]
  })
}

# IAM Role (CloudWatch -> Firehose)
resource "aws_iam_role" "cw_firehose_role" {
  name = "${var.name}-cw-to-firehose"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", 
    Statement = [{ 
        Action = "sts:AssumeRole", 
        Effect = "Allow", 
        Principal = { 
            Service = "logs.${var.region}.amazonaws.com" 
        } 
    }]
  })
}

resource "aws_iam_role_policy" "cw_firehose" {
  name = "cw-firehose"
  role = aws_iam_role.cw_firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17", 
    Statement = [{ 
        Effect = "Allow", 
        Action = ["firehose:PutRecord", "firehose:PutRecordBatch"], Resource = "*" 
    }]
  })
}

# Firehose Stream
resource "aws_kinesis_firehose_delivery_stream" "log_stream" {
  name        = "${var.name}-log-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.log_bucket.arn
    buffering_size     = 5
    buffering_interval = 300
    compression_format = "GZIP"
  }
}

# Subscription Filter
resource "aws_cloudwatch_log_subscription_filter" "log_filter" {
  name            = "${var.name}-filter"
  role_arn        = aws_iam_role.cw_firehose_role.arn
  log_group_name  = var.app_log_group_name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.log_stream.arn
}