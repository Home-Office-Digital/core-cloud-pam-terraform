resource "aws_cloudtrail_event_data_store" "team_data_store" {
  name                           = var.name
  organization_enabled           = var.organization_enabled
  retention_period               = var.retention_period
  tags                           = var.tags
  termination_protection_enabled = true
  kms_key_id                     = aws_kms_key.cloudtrail_eds.arn
}

resource "aws_kms_key" "cloudtrail_eds" {
  description             = "CMK for CloudTrail Event Data Store"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = data.aws_iam_policy_document.cloudtrail_kms.json
}

resource "aws_kms_alias" "cloudtrail_eds" {
  name          = "alias/cloudtrail-event-data-store"
  target_key_id = aws_kms_key.cloudtrail_eds.key_id
}

data "aws_iam_policy_document" "cloudtrail_kms" {
  statement {
    sid = "Allow CloudTrail to use the key"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }
}
