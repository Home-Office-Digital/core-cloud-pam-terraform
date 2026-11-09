mock_provider "aws" {}

# Consumers run Terraform 1.9.3 and validate tests/ on init - keep to syntax it supports.

variables {
  name = "TEAM-AppStream-Registry-test"
  applications = {
    "APC-PR-Prod-WL-Account-1" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    "APC-PR-Prod-WL-Account-2" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
  }
}

# File-level, so every run gets them. The mock provider would otherwise invent an
# organization with no matching accounts and a policy document the real schema rejects.
override_data {
  target = data.aws_organizations_organization.this
  values = {
    accounts = [
      { name = "APC-PR-Prod-WL-Account-1", id = "111111111111", status = "ACTIVE", arn = "arn:aws:organizations::000000000000:account/o-test/111111111111", email = "a@example.com" },
      { name = "APC-PR-Prod-WL-Account-2", id = "222222222222", status = "ACTIVE", arn = "arn:aws:organizations::000000000000:account/o-test/222222222222", email = "b@example.com" },
      { name = "Duplicated-Name", id = "333333333333", status = "ACTIVE", arn = "arn:aws:organizations::000000000000:account/o-test/333333333333", email = "c@example.com" },
      { name = "Duplicated-Name", id = "444444444444", status = "ACTIVE", arn = "arn:aws:organizations::000000000000:account/o-test/444444444444", email = "d@example.com" },
      { name = "Suspended-Account", id = "555555555555", status = "SUSPENDED", arn = "arn:aws:organizations::000000000000:account/o-test/555555555555", email = "e@example.com" },
    ]
  }
}

override_data {
  target = data.aws_iam_policy_document.appstream_registry_kms
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

# apply, not plan: the SSE assertion reads the computed key ARN.
run "design_constraints" {
  command = apply

  override_resource {
    target = aws_kms_key.appstream_registry
    values = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/test-key-id"
      key_id = "test-key-id"
    }
  }

  assert {
    condition     = aws_dynamodb_table.appstream_registry.hash_key == "accountId"
    error_message = "Registry must be keyed on accountId, which TEAM verifies; accountName can be client-supplied."
  }

  # Keyed by ID so renaming an account updates its item in place, rather than a create and a
  # destroy racing against the same row.
  assert {
    condition     = toset(keys(aws_dynamodb_table_item.application)) == toset(["111111111111", "222222222222"])
    error_message = "Item instances must be keyed by resolved account ID, not account name."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.application["111111111111"].item).accountId.S == "111111111111"
    error_message = "Account names must be resolved to their account ID."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.application["111111111111"].item).accountName.S == "APC-PR-Prod-WL-Account-1"
    error_message = "The account name must be kept on the item for readability."
  }

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.application["222222222222"].item).applicationArn.S == "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    error_message = "Items must carry applicationArn as a string attribute."
  }

  # kms_key_arn is optional, so dropping it would silently fall back to the AWS managed key.
  assert {
    condition     = aws_dynamodb_table.appstream_registry.server_side_encryption[0].kms_key_arn == aws_kms_key.appstream_registry.arn
    error_message = "Table must be encrypted with the module's own CMK."
  }

  # The controller finds the key by this alias.
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

# A typo must fail the plan, not write a row that never matches.
run "rejects_unknown_account_name" {
  command = plan

  variables {
    applications = {
      "APC-PR-Prod-WL-Acount-1" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    }
  }

  expect_failures = [aws_dynamodb_table_item.application]
}

# Two active accounts with one name: refuse rather than guess.
run "rejects_ambiguous_account_name" {
  command = plan

  variables {
    applications = {
      "Duplicated-Name" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    }
  }

  expect_failures = [aws_dynamodb_table_item.application]
}

# A suspended account must not resolve.
run "rejects_suspended_account" {
  command = plan

  variables {
    applications = {
      "Suspended-Account" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    }
  }

  expect_failures = [aws_dynamodb_table_item.application]
}

run "rejects_name_outside_convention" {
  command = plan

  variables {
    name = "team-appstream-registry"
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

  expect_failures = [var.applications]
}
