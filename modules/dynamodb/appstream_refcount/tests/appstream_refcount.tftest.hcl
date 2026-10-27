mock_provider "aws" {}

# Checkov already gates PITR (CKV_AWS_28) and CMK encryption (CKV_AWS_119), and a change to
# the key schema forces table replacement, which deletion protection turns into a failed
# apply. What is left unguarded is the schema and TTL design, where a well-meaning change
# would break reference counting silently.
run "design_constraints" {
  command = plan

  variables {
    name = "TEAM-AppStream-RefCount-test"
  }

  # activeRequestIds must stay schemaless so it remains a String Set and supports atomic
  # ADD / DELETE. Declaring it would make it a List and force read-modify-write.
  assert {
    condition     = length(aws_dynamodb_table.appstream_refcount.attribute) == 2
    error_message = "Only the two key attributes may be declared; activeRequestIds must stay schemaless."
  }

  # A TTL could expire a counter still holding a live assignment open.
  assert {
    condition     = length(aws_dynamodb_table.appstream_refcount.ttl) == 0 ? true : aws_dynamodb_table.appstream_refcount.ttl[0].enabled == false
    error_message = "TTL must not be enabled on the reference-count table."
  }
}

# The table name is the only coupling between this module and the state machines in
# core-cloud-pam-team-app, and it is a convention rather than a reference. A mismatch fails
# silently: the UpdateItem calls would target a table that does not exist, so every set
# would look empty.
run "rejects_name_outside_convention" {
  command = plan

  variables {
    name = "team-appstream-refcount"
  }

  expect_failures = [var.name]
}

# Checkov passes CKV_AWS_119 on the presence of the kms_key_arn reference alone, so it does
# not actually prove a supplied key reaches the table.
run "customer_managed_key_is_used" {
  command = plan

  variables {
    name        = "TEAM-AppStream-RefCount-dev"
    kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
  }

  assert {
    condition     = aws_dynamodb_table.appstream_refcount.server_side_encryption[0].kms_key_arn == "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
    error_message = "A supplied customer managed key must be used for encryption."
  }
}
