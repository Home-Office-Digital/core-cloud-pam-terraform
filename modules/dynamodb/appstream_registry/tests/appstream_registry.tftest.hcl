mock_provider "aws" {}

# Keep this file to syntax the oldest consuming Terraform supports (1.9.3 in
# core-cloud-pam-team-terragrunt). Consumers download tests/ with the module and Terraform
# validates the whole configuration during init, so newer syntax breaks their plan.

variables {
  name = "TEAM-AppStream-Registry-test"
  applications = {
    "APC-PR-Prod-WL-Account-1" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    "APC-PR-Prod-WL-Account-2" = "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
  }
}

run "design_constraints" {
  command = plan

  # The state machines look up by $.accountName. A different key would make every lookup
  # miss, so nobody would get AppStream.
  assert {
    condition     = aws_dynamodb_table.appstream_registry.hash_key == "accountName"
    error_message = "Registry must be keyed on accountName, which the state machines look up by."
  }

  assert {
    condition     = length(aws_dynamodb_table_item.application) == 2
    error_message = "One registry item must be written per mapped account."
  }

  # The state machines read applicationArn.S from the lookup result.
  assert {
    condition     = jsondecode(aws_dynamodb_table_item.application["APC-PR-Prod-WL-Account-1"].item).applicationArn.S == "arn:aws:sso::111122223333:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
    error_message = "Items must carry applicationArn as a string attribute."
  }
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

  variables {
    applications = {
      "APC-PR-Prod-WL-Account-1" = "PAM Live"
    }
  }

  expect_failures = [var.applications]
}
