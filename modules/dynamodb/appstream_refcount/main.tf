# Reference-count table for ephemeral AppStream (IdC application) assignments driven
# by the TEAM session lifecycle. See README.md for the design rationale.

resource "aws_dynamodb_table" "appstream_refcount" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"

  # Composite key rather than a single concatenated value so the reconciliation
  # sweep can Query every principal holding a given application. Do not collapse
  # these into one attribute.
  hash_key  = "applicationArn"
  range_key = "principalId"

  attribute {
    name = "applicationArn"
    type = "S"
  }

  attribute {
    name = "principalId"
    type = "S"
  }

  # Do not declare activeRequestIds here. DynamoDB only requires key attributes,
  # and it must stay a String Set: atomic ADD / DELETE update expressions only work
  # on sets. Declaring it (or modelling it as a List) forces read-modify-write and
  # reintroduces the race this table exists to remove.

  # Do not add a TTL. Once a set empties the row persists as a key-only tombstone, which
  # makes a TTL look like a tidy way to reap them - but a timestamp written at grant time
  # can fire while the set is still non-empty and delete a live counter. See README.md,
  # which also covers why consumers must test for the attribute and not the row.

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.appstream_refcount.arn
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = var.tags

  # The key is created with the default account-only policy and the policy below is
  # attached separately, so without this the table could be created against the
  # transient default policy. Keeps the ordering deterministic.
  depends_on = [aws_kms_key_policy.appstream_refcount]
}

resource "aws_kms_key" "appstream_refcount" {
  description             = "CMK for the TEAM AppStream assignment reference-count table"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}

resource "aws_kms_alias" "appstream_refcount" {
  # Mirrors the table name exactly rather than being fixed or case-folded. Fixed would
  # collide if the module were deployed twice in an account; lower() would also collide,
  # because var.name permits a mixed-case env suffix and DynamoDB table names are
  # case-sensitive, so TEAM-AppStream-RefCount-dev and -DEV are distinct tables that both
  # fold to one alias. KMS aliases allow uppercase, so mirroring inherits the table's own
  # uniqueness and needs no mapping to reason about.
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.appstream_refcount.key_id
}

# Attached separately rather than inline on aws_kms_key. Inline, the key depends on the
# policy document, so the document cannot reference the key's own ARN and resources would
# have to be "*" - which trips CKV_AWS_356.
resource "aws_kms_key_policy" "appstream_refcount" {
  key_id = aws_kms_key.appstream_refcount.id
  policy = data.aws_iam_policy_document.appstream_refcount_kms.json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "appstream_refcount_kms" {
  # Without this the key would have no administrator once the policy is applied and the
  # policy could never be changed again. AWS's policy lockout safety check also rejects a
  # key policy that does not grant the account root kms:PutKeyPolicy. DynamoDB itself needs
  # no service statement: it creates grants on the key on behalf of the calling principal.
  statement {
    sid = "Allow account administration of the key"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = [aws_kms_key.appstream_refcount.arn]
  }
}
