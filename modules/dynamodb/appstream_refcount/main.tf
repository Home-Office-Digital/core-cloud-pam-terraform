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

  # Do not add a TTL. Entries disappear when their set empties; a TTL could expire a
  # counter that is still holding a live assignment open.

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = var.tags
}
