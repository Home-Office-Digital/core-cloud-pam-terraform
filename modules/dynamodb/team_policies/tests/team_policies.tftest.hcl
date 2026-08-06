mock_provider "aws" {}

run "plan_with_empty_policy_sets" {
  command = plan

  variables {
    approvers_table_name   = "team-approvers"
    eligibility_table_name = "team-eligibility"
    approvers_policies     = []
    eligibility_policies   = []
  }

  override_data {
    target = data.aws_dynamodb_table.approvers_table
    values = {
      name     = "team-approvers"
      hash_key = "id"
    }
  }

  override_data {
    target = data.aws_dynamodb_table.eligibility_table
    values = {
      name     = "team-eligibility"
      hash_key = "id"
    }
  }

  override_data {
    target = data.aws_organizations_organization.this
    values = {
      roots = [
        {
          id = "r-root"
        }
      ]
      accounts = []
    }
  }

  override_data {
    target = data.aws_organizations_organizational_units.level1_ous
    values = {
      children = []
    }
  }

  assert {
    condition     = length(aws_dynamodb_table_item.approvers) == 0
    error_message = "No approver items should be created for an empty policy list."
  }

  assert {
    condition     = data.aws_dynamodb_table.approvers_table.hash_key == "id"
    error_message = "Approvers table hash key should be id in this test setup."
  }

  assert {
    condition     = length(aws_dynamodb_table_item.eligibility) == 0
    error_message = "No eligibility items should be created for an empty policy list."
  }

  assert {
    condition     = data.aws_dynamodb_table.eligibility_table.hash_key == "id"
    error_message = "Eligibility table hash key should be id in this test setup."
  }
}

run "plan_with_single_policy_set" {
  command = plan

  variables {
    approvers_table_name   = "team-approvers"
    eligibility_table_name = "team-eligibility"

    approvers_policies = [
      {
        type             = "account"
        name             = "Sandbox"
        ticket_no        = "CHG0001"
        approvers_groups = ["TEAM-Approvers"]
      }
    ]

    eligibility_policies = [
      {
        group_name        = "TEAM-Eligible"
        accounts          = ["Sandbox"]
        approval_required = true
        duration          = 60
        ous               = ["Root"]
        permissions       = ["ReadOnlyAccess"]
        ticket_no         = "CHG0002"
      }
    ]
  }

  override_data {
    target = data.aws_dynamodb_table.approvers_table
    values = {
      name     = "team-approvers"
      hash_key = "id"
    }
  }

  override_data {
    target = data.aws_dynamodb_table.eligibility_table
    values = {
      name     = "team-eligibility"
      hash_key = "id"
    }
  }

  override_data {
    target = data.aws_ssoadmin_instances.this
    values = {
      identity_store_ids = ["d-1234567890"]
      arns               = ["arn:aws:sso:::instance/ssoins-1234567890"]
    }
  }

  override_data {
    target = data.aws_organizations_organization.this
    values = {
      roots = [
        {
          id = "r-root"
        }
      ]
      accounts = [
        {
          id   = "111122223333"
          name = "Sandbox"
        }
      ]
    }
  }

  override_data {
    target = data.aws_organizations_organizational_units.level1_ous
    values = {
      children = []
    }
  }

  override_data {
    target = data.aws_identitystore_group.approvers_group["TEAM-Approvers"]
    values = {
      group_id     = "group-approvers-1"
      display_name = "TEAM-Approvers"
    }
  }

  override_data {
    target = data.aws_identitystore_group.eligibility_group["TEAM-Eligible"]
    values = {
      group_id     = "group-eligible-1"
      display_name = "TEAM-Eligible"
    }
  }

  override_data {
    target = data.aws_ssoadmin_permission_set.this["ReadOnlyAccess"]
    values = {
      id = "ps-readonly"
    }
  }

  assert {
    condition     = length(aws_dynamodb_table_item.approvers) == 1
    error_message = "One approver item should be created for one approvers policy."
  }

  assert {
    condition     = length(aws_dynamodb_table_item.eligibility) == 1
    error_message = "One eligibility item should be created for one eligibility policy."
  }

  assert {
    condition     = jsondecode(values(aws_dynamodb_table_item.approvers)[0].item).type.S == "Account"
    error_message = "Approvers item type should be Account for account-based policy."
  }

  assert {
    condition     = jsondecode(values(aws_dynamodb_table_item.eligibility)[0].item).approvalRequired.BOOL == true
    error_message = "Eligibility item should preserve approval_required as true."
  }
}
