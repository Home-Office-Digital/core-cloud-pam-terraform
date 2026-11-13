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

  # Instances keyed by account ID, so renaming an account updates its item in place rather
  # than creating a new instance and destroying the old one against the same row.
  items = {
    for name, arns in var.applications :
    (length(lookup(local.account_ids, name, [])) == 1 ? local.account_ids[name][0] : "unresolved:${name}") => { name = name, arns = arns }
  }
}

resource "aws_dynamodb_table_item" "application" {
  for_each = local.items

  table_name = aws_dynamodb_table.appstream_registry.name
  hash_key   = aws_dynamodb_table.appstream_registry.hash_key

  item = jsonencode({
    accountId       = { S = each.key }
    accountName     = { S = each.value.name }
    applicationArns = { SS = sort(each.value.arns) }
    # The first application, for controllers before 0.17.0, which read a single ARN.
    applicationArn = { S = each.value.arns[0] }
  })

  lifecycle {
    precondition {
      condition     = !startswith(each.key, "unresolved:")
      error_message = "Account \"${each.value.name}\" must match exactly one active account in the organization."
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
  # Required by the lockout safety check, and delegates to IAM for the apply and controller roles.
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
