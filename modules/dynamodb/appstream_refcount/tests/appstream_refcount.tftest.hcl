mock_provider "aws" {}

# Checkov already gates PITR (CKV_AWS_28), and a change to the key schema forces table
# replacement, which deletion protection turns into a failed apply. What is left
# unguarded is the schema and TTL design, where a well-meaning change would break
# reference counting silently, and the CMK wiring, where removal silently downgrades the
# table to the AWS managed key.
run "design_constraints" {
  command = plan

  variables {
    name = "TEAM-AppStream-RefCount-test"
  }

  # override_during = plan is required: arn is computed, so without it the SSE assertion
  # below cannot be evaluated at plan time.
  override_resource {
    target          = aws_kms_key.appstream_refcount
    override_during = plan
    values = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/test-key-id"
      key_id = "test-key-id"
    }
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

  # kms_key_arn is optional on aws_dynamodb_table, so dropping this reference would not
  # error - the table would quietly fall back to the AWS managed aws/dynamodb key and
  # reintroduce CKV_AWS_119.
  assert {
    condition     = aws_dynamodb_table.appstream_refcount.server_side_encryption[0].kms_key_arn == aws_kms_key.appstream_refcount.arn
    error_message = "Table must be encrypted with the module's own CMK, not the AWS managed key."
  }

  assert {
    condition     = aws_kms_key.appstream_refcount.enable_key_rotation == true
    error_message = "Key rotation must be enabled on the CMK."
  }

  # A fixed alias would collide if the module were deployed twice in one account, and a
  # case-folded one would collide between env suffixes differing only by case.
  assert {
    condition     = aws_kms_alias.appstream_refcount.name == "alias/TEAM-AppStream-RefCount-test"
    error_message = "Alias must mirror the table name exactly, without case folding."
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
