mock_provider "aws" {}

# These assertions guard the design constraints in README.md rather than re-testing
# Terraform's own variable plumbing.
run "design_constraints" {
  command = plan

  variables {
    name = "TEAM-AppStream-RefCount-test"
  }

  # Composite key is what lets the reconciliation sweep Query every principal
  # holding a given application.
  assert {
    condition     = aws_dynamodb_table.appstream_refcount.hash_key == "applicationArn"
    error_message = "Hash key must be applicationArn so the sweep can Query per application."
  }

  assert {
    condition     = aws_dynamodb_table.appstream_refcount.range_key == "principalId"
    error_message = "Range key must be principalId."
  }

  # activeRequestIds must remain schemaless so it stays a String Set and supports
  # atomic ADD / DELETE. Declaring it would make it a List.
  assert {
    condition     = length(aws_dynamodb_table.appstream_refcount.attribute) == 2
    error_message = "Only the two key attributes may be declared; activeRequestIds must stay schemaless."
  }

  # A TTL could expire a counter still holding a live assignment open.
  assert {
    condition     = length(aws_dynamodb_table.appstream_refcount.ttl) == 0 ? true : aws_dynamodb_table.appstream_refcount.ttl[0].enabled == false
    error_message = "TTL must not be enabled on the reference-count table."
  }

  assert {
    condition     = aws_dynamodb_table.appstream_refcount.server_side_encryption[0].enabled == true
    error_message = "Server-side encryption must be enabled."
  }

  # Losing the table mid-session strands AppStream assignments, so both of these
  # default on and must be opted out of explicitly.
  assert {
    condition     = aws_dynamodb_table.appstream_refcount.deletion_protection_enabled == true
    error_message = "Deletion protection must default to enabled."
  }

  assert {
    condition     = aws_dynamodb_table.appstream_refcount.point_in_time_recovery[0].enabled == true
    error_message = "Point-in-time recovery must default to enabled."
  }
}

#  The table name is the only coupling between this module and the state machines in
#  core-cloud-pam-team-app, and it is a naming convention rather than a reference.
#  A mismatch fails silently, so the convention is enforced here.
run "rejects_name_outside_convention" {
  command = plan

  variables {
    name = "team-appstream-refcount"
  }

  expect_failures = [var.name]
}

run "non_production_overrides" {
  command = plan

  variables {
    name                           = "TEAM-AppStream-RefCount-dev"
    kms_key_arn                    = "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
    point_in_time_recovery_enabled = false
    deletion_protection_enabled    = false
  }

  # Confirms the key is wired into the SSE block rather than silently ignored.
  assert {
    condition     = aws_dynamodb_table.appstream_refcount.server_side_encryption[0].kms_key_arn == "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
    error_message = "A supplied customer managed key must be used for encryption."
  }

  assert {
    condition     = aws_dynamodb_table.appstream_refcount.point_in_time_recovery[0].enabled == false
    error_message = "Point-in-time recovery must be overridable for non-production."
  }

  assert {
    condition     = aws_dynamodb_table.appstream_refcount.deletion_protection_enabled == false
    error_message = "Deletion protection must be overridable for non-production."
  }
}
