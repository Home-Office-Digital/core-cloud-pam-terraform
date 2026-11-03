# Maps a TEAM account to the AppStream application its sessions are granted. See README.md.
resource "aws_dynamodb_table" "appstream_registry" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"

  # accountId, not accountName: TEAM keeps a client-supplied accountName when it cannot
  # resolve one, whereas accountId is what eligibility and the account assignment use.
  hash_key = "accountId"

  attribute {
    name = "accountId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.appstream_registry.arn
  }

  deletion_protection_enabled = true
  tags                        = var.tags

  # Keeps the table from being created against the key's transient default policy.
  depends_on = [aws_kms_key_policy.appstream_registry]
}

data "aws_organizations_organization" "this" {}

locals {
  # Grouped, so a name shared by two active accounts is caught rather than silently picking one.
  account_ids = { for a in data.aws_organizations_organization.this.accounts : a.name => a.id... if a.status == "ACTIVE" }
}

resource "aws_dynamodb_table_item" "application" {
  for_each = var.applications

  table_name = aws_dynamodb_table.appstream_registry.name
  hash_key   = aws_dynamodb_table.appstream_registry.hash_key

  item = jsonencode({
    accountId      = { S = one(lookup(local.account_ids, each.key, [""])) }
    accountName    = { S = each.key }
    applicationArn = { S = each.value }
  })

  lifecycle {
    precondition {
      condition     = length(lookup(local.account_ids, each.key, [])) == 1
      error_message = "Account \"${each.key}\" must match exactly one active account in the organization."
    }
  }
}

resource "aws_kms_key" "appstream_registry" {
  description             = "CMK for the TEAM AppStream application registry"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}

resource "aws_kms_alias" "appstream_registry" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.appstream_registry.key_id
}

# Separate from aws_kms_key so the policy can reference the key's own ARN.
resource "aws_kms_key_policy" "appstream_registry" {
  key_id = aws_kms_key.appstream_registry.id
  policy = data.aws_iam_policy_document.appstream_registry_kms.json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "appstream_registry_kms" {
  # Required by the lockout safety check, and delegates to IAM for the apply and state machine roles.
  statement {
    sid = "Allow account administration of the key"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = [aws_kms_key.appstream_registry.arn]
  }

  # Granted here rather than in IAM because the baseline IAM module drops conditions.
  dynamic "statement" {
    for_each = length(var.reader_role_arns) > 0 ? [1] : []

    content {
      sid = "Allow readers to decrypt via DynamoDB only"

      principals {
        type        = "AWS"
        identifiers = var.reader_role_arns
      }

      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [aws_kms_key.appstream_registry.arn]

      condition {
        test     = "StringLike"
        variable = "kms:ViaService"
        values   = ["dynamodb.*.amazonaws.com"]
      }
    }
  }
}
