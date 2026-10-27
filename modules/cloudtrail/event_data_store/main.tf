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
}

# The policy is attached separately rather than inline on aws_kms_key. Inline, the key
# depends on the policy document, so the document cannot reference the key's own ARN and
# resources has to be "*". Attaching it here inverts that: the document can scope each
# statement to this key.
resource "aws_kms_key_policy" "cloudtrail_eds" {
  key_id = aws_kms_key.cloudtrail_eds.id
  policy = data.aws_iam_policy_document.cloudtrail_kms.json
}

resource "aws_kms_alias" "cloudtrail_eds" {
  name          = "alias/cloudtrail-event-data-store"
  target_key_id = aws_kms_key.cloudtrail_eds.key_id
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "cloudtrail_kms" {
  # Without this statement the key would have no administrator once the policy is applied,
  # and the policy itself could never be changed again. AWS's policy lockout safety check
  # also rejects a key policy that does not grant the account root kms:PutKeyPolicy.
  statement {
    sid = "Allow account administration of the key"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = [aws_kms_key.cloudtrail_eds.arn]
  }

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

    resources = [aws_kms_key.cloudtrail_eds.arn]
  }
}
