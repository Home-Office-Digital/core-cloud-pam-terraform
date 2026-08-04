data "aws_dynamodb_table" "eligibility_table" {
  name = var.eligibility_table_name
}

data "aws_dynamodb_table" "approvers_table" {
  name = var.approvers_table_name
}

data "aws_ssoadmin_instances" "this" {}

data "aws_organizations_organization" "this" {}

data "aws_organizations_organizational_units" "level1_ous" {
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

data "aws_organizations_organizational_units" "level2_ous" {
  for_each  = { for ou in data.aws_organizations_organizational_units.level1_ous.children : ou.id => ou }
  parent_id = each.key
}

data "aws_organizations_organizational_units" "level3_ous" {
  for_each = merge([
    for parent in data.aws_organizations_organizational_units.level2_ous :
    { for child in parent.children : child.id => child }
  ]...)

  parent_id = each.key
}

data "aws_organizations_organizational_units" "level4_ous" {
  for_each = merge([
    for parent in data.aws_organizations_organizational_units.level3_ous :
    { for child in parent.children : child.id => child }
  ]...)

  parent_id = each.key
}

# Build a list of maps of all OUs with their full path and ID
# [
#   {
#     id   = "ou-abc1-1234abc"
#     name = "Workloads/NotProd"
#   },
#   ....
# ]
locals {
  # Root OU
  root_ou = [{
    id   = data.aws_organizations_organization.this.roots[0].id
    name = "Root"
  }]

  # Top-level OUs, e.g. Workloads, Products, Security, Infrastructure
  top_level_ous = [
    for ou in data.aws_organizations_organizational_units.level1_ous.children : {
      id   = ou.id
      name = ou.name
    }
  ]

  # Second-level OUs, e.g. Workloads/Portfolio, Products/NotLive
  second_level_ous = flatten([
    for parent_ou_id, ous in data.aws_organizations_organizational_units.level2_ous : [
      for ou in ous.children : {
        id = ou.id
        name = "${lookup(
          { for ou in local.top_level_ous : ou.id => ou.name },
          parent_ou_id,
          "UNKNOWN"
        )}/${ou.name}"
      }
    ]
  ])

  # Third-level OUs, e.g. Workloads/Portfolio/ProductFamily
  third_level_ous = flatten([
    for parent_ou_id, ous in data.aws_organizations_organizational_units.level3_ous : [
      for ou in ous.children : {
        id = ou.id
        name = "${lookup(
          { for ou in local.second_level_ous : ou.id => ou.name },
          parent_ou_id,
          "UNKNOWN"
        )}/${ou.name}"
      }
    ]
  ])

  # Fourth-level OUs, e.g. Workloads/Portfolio/ProductFamily/NotProd
  fourth_level_ous = flatten([
    for parent_ou_id, ous in data.aws_organizations_organizational_units.level4_ous : [
      for ou in ous.children : {
        id = ou.id
        name = "${lookup(
          { for ou in local.third_level_ous : ou.id => ou.name },
          parent_ou_id,
          "UNKNOWN"
        )}/${ou.name}"
      }
    ]
  ])

  all_ous = concat(local.root_ou, local.top_level_ous, local.second_level_ous, local.third_level_ous, local.fourth_level_ous)
}

# Read all unique approvers groups
locals {
  unique_approvers_group_names = toset(flatten([for policy in var.approvers_policies : policy.approvers_groups]))
}

data "aws_identitystore_group" "approvers_group" {
  for_each = local.unique_approvers_group_names

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

data "aws_identitystore_group" "eligibility_group" {
  for_each = { for policy in var.eligibility_policies : policy.group_name => policy }

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value.group_name
    }
  }
}

# Read all unique Permissions Sets
locals {
  unique_permission_set_names = toset(flatten([for policy in var.eligibility_policies : policy.permissions]))
}

data "aws_ssoadmin_permission_set" "this" {
  for_each = local.unique_permission_set_names

  instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  name         = each.value
}

locals {
  eligibility_items = {
    for i, policy in var.eligibility_policies : i => jsonencode({
      id = {
        S = data.aws_identitystore_group.eligibility_group[policy.group_name].group_id
      },
      accounts = {
        L = [
          for account in policy.accounts : {
            M = {
              id   = { S = tostring(one([for acct in data.aws_organizations_organization.this.accounts : acct.id if acct.name == account])) },
              name = { S = account }
            }
          }
        ]
      },
      approvalRequired = {
        BOOL = policy.approval_required
      },
      createdAt = {
        S = "2025-06-24T09:00:00Z"
      },
      duration = {
        S = "${tostring(policy.duration)}"
      },
      modifiedBy = {
        S = "Terraform"
      },
      name = {
        S = "${data.aws_identitystore_group.eligibility_group[policy.group_name].display_name}"
      },
      ous = {
        L = [
          for ou in policy.ous : {
            M = {
              id   = { S = tostring(one([for org_unit in local.all_ous : org_unit.id if org_unit.name == ou])) },
              name = { S = element(split("/", ou), length(split("/", ou)) - 1) }
            }
          }
        ]
      },
      permissions = {
        L = [
          for permission in policy.permissions : {
            M = {
              id   = { S = data.aws_ssoadmin_permission_set.this[permission].id },
              name = { S = permission }
            }
          }
        ]
      }
      ticketNo = {
        S = "${policy.ticket_no}"
      },
      type = {
        S = "Group"
      },
      updatedAt = {
        S = "2025-06-24T09:00:00Z"
      },
      __typename = {
        S = "Eligibility"
      }
    })
  }
}

locals {
  approvers_items = {
    for i, policy in var.approvers_policies : i => jsonencode({
      id = {
        S = lower(policy.type) == "account" ? tostring(one([for acct in data.aws_organizations_organization.this.accounts : acct.id if acct.name == policy.name])) : tostring(one([for ou in local.all_ous : ou.id if ou.name == policy.name]))
      },
      approvers = {
        L = [
          for approvers_group in policy.approvers_groups :
          { S = data.aws_identitystore_group.approvers_group[approvers_group].display_name }
        ]
      },
      createdAt = {
        S = "2025-06-24T09:00:00Z"
      },
      groupIds = {
        L = [
          for approvers_group in policy.approvers_groups :
          { S = data.aws_identitystore_group.approvers_group[approvers_group].group_id }
        ]
      },
      modifiedBy = {
        S = "Terraform"
      },
      name = {
        S = lower(policy.type) == "account" ? policy.name : element(split("/", policy.name), length(split("/", policy.name)) - 1)
      },
      ticketNo = {
        S = policy.ticket_no
      },
      type = {
        S = lower(policy.type) == "account" ? "Account" : "OU"
      },
      updatedAt = {
        S = "2025-06-24T09:00:00Z"
      },
      __typename = {
        S = "Approvers"
      }
    })
  }
}

resource "aws_dynamodb_table_item" "eligibility" {
  for_each = local.eligibility_items

  table_name = data.aws_dynamodb_table.eligibility_table.name
  hash_key   = data.aws_dynamodb_table.eligibility_table.hash_key
  item       = each.value
}

resource "aws_dynamodb_table_item" "approvers" {
  for_each = local.approvers_items

  table_name = data.aws_dynamodb_table.approvers_table.name
  hash_key   = data.aws_dynamodb_table.approvers_table.hash_key
  item       = each.value
}
