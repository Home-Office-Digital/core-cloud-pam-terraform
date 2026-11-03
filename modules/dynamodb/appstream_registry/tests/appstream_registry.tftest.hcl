mock_provider "aws" {}

# Consumers run Terraform 1.9.3 and validate tests/ on init - keep to syntax it supports.

variables {
  name = "TEAM-AppStream-Registry-test"
  applications = {
    "APC-PR-Prod-WL-Account-1" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    "APC-PR-Prod-WL-Account-2" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
  }
}

# apply, not plan: the SSE assertion reads the key ARN, which is computed. The overrides give
# the mock provider values the real schemas accept.
run "design_constraints" {
  command = apply

  override_data {
    target = data.aws_iam_policy_document.appstream_registry_kms
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_kms_key.appstream_registry
    values = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/test-key-id"
      key_id = "test-key-id"
    }
  }

  assert {
    condition     = aws_dynamodb_table.appstream_registry.hash_key == "accountName"
    error_message = "Registry must be keyed on accountName, which the state machines look up by."
  }

  assert {
    condition     = length(aws_dynamodb_table_item.application) == 2
    error_message = "One item must be written per mapped account."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.application["APC-PR-Prod-WL-Account-1"].item).applicationArn.S == "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    error_message = "Items must carry applicationArn as a string attribute."
  }

  # kms_key_arn is optional, so dropping it would silently fall back to the AWS managed key.
  assert {
    condition     = aws_dynamodb_table.appstream_registry.server_side_encryption[0].kms_key_arn == aws_kms_key.appstream_registry.arn
    error_message = "Table must be encrypted with the module's own CMK."
  }

  # The Grant state machine's KMS condition matches on this alias.
  assert {
    condition     = aws_kms_alias.appstream_registry.name == "alias/TEAM-AppStream-Registry-test"
    error_message = "Alias must mirror the table name."
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.appstream_registry_kms.statement : s if s.sid == "Allow readers to decrypt via DynamoDB only"]) == 0
    error_message = "No reader statement may be rendered when reader_role_arns is empty."
  }
}

# Asserts on the configured statement, not the rendered JSON, which is overridden above.
run "reader_grant_is_read_only_and_dynamodb_only" {
  command = apply

  variables {
    reader_role_arns = ["arn:aws:iam::111122223333:role/cc-pam-team-terragrunt-plan-role"]
  }

  override_data {
    target = data.aws_iam_policy_document.appstream_registry_kms
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_kms_key.appstream_registry
    values = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/test-key-id"
      key_id = "test-key-id"
    }
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.appstream_registry_kms.statement : s if s.sid == "Allow readers to decrypt via DynamoDB only"]) == 1
    error_message = "Exactly one reader statement must be rendered when reader_role_arns is set."
  }

  assert {
    condition     = one(one([for s in data.aws_iam_policy_document.appstream_registry_kms.statement : s if s.sid == "Allow readers to decrypt via DynamoDB only"]).principals).identifiers == toset(["arn:aws:iam::111122223333:role/cc-pam-team-terragrunt-plan-role"])
    error_message = "Reader statement must grant exactly the configured roles."
  }

  assert {
    condition     = toset(one([for s in data.aws_iam_policy_document.appstream_registry_kms.statement : s if s.sid == "Allow readers to decrypt via DynamoDB only"]).actions) == toset(["kms:Decrypt", "kms:DescribeKey"])
    error_message = "Reader statement must be read-only: kms:Decrypt and kms:DescribeKey only."
  }

  assert {
    condition = anytrue([
      for c in one([for s in data.aws_iam_policy_document.appstream_registry_kms.statement : s if s.sid == "Allow readers to decrypt via DynamoDB only"]).condition :
      c.variable == "kms:ViaService" && c.test == "StringLike" && toset(c.values) == toset(["dynamodb.*.amazonaws.com"])
    ])
    error_message = "Reader statement must be limited to calls via DynamoDB with kms:ViaService."
  }
}

run "rejects_name_outside_convention" {
  command = plan

  variables {
    name = "team-appstream-registry"
  }

  override_data {
    target = data.aws_iam_policy_document.appstream_registry_kms
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  expect_failures = [var.name]
}

run "rejects_malformed_application_arn" {
  command = plan

  # Well-shaped but with IDs shorter than the 16 characters AWS requires.
  variables {
    applications = {
      "APC-PR-Prod-WL-Account-1" = "arn:aws:sso::111122223333:application/ssoins-a/apl-b"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.appstream_registry_kms
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  expect_failures = [var.applications]
}
