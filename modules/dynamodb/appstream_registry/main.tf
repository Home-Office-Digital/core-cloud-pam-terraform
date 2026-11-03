# Registry mapping a TEAM target account to the IdC (AppStream) application that a session
# for that account should be granted. Read by the TEAM Grant and Revoke state machines, so
# adding a tenant is a row here rather than a change to the shared TEAM app. See README.md.
resource "aws_dynamodb_table" "appstream_registry" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"

  # Keyed on the name TEAM carries as $.accountName. A renamed account simply stops
  # matching, which fails closed: no AppStream, and the TEAM session proceeds as normal.
  hash_key = "accountName"

  attribute {
    name = "accountName"
    type = "S"
  }

  # The table is rebuilt from Terraform, but CKV_AWS_28 is HIGH and blocks the SAST gate.
  point_in_time_recovery {
    enabled = true
  }

  # AWS managed key, unlike appstream_refcount. Terraform reads these items on every plan,
  # so a CMK would need kms:Decrypt on the read-only plan role - and the shared IAM module
  # cannot scope that with kms:ViaService, so it would decrypt any IAM-delegating key in the
  # account. The table holds account names and application ARNs only.
  #checkov:skip=CKV_AWS_119:Non-sensitive config. A CMK would force unscoped kms:Decrypt onto the plan role.
  server_side_encryption {
    enabled = true
  }

  # Losing the table fails closed - no AppStream for anyone - rather than open.
  deletion_protection_enabled = true

  tags = var.tags
}

resource "aws_dynamodb_table_item" "application" {
  for_each = var.applications

  table_name = aws_dynamodb_table.appstream_registry.name
  hash_key   = aws_dynamodb_table.appstream_registry.hash_key

  item = jsonencode({
    accountName    = { S = each.key }
    applicationArn = { S = each.value }
  })
}
