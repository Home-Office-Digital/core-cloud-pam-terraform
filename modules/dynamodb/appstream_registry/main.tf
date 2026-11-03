# Maps a TEAM account to the AppStream application its sessions are granted. See README.md.
resource "aws_dynamodb_table" "appstream_registry" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "accountName"

  attribute {
    name = "accountName"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  #checkov:skip=CKV_AWS_119:Non-sensitive config. A CMK would force unscoped kms:Decrypt onto the plan role.
  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true
  tags                        = var.tags
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
