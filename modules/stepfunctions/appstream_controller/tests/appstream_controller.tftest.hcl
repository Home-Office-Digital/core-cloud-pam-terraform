# Computed ARNs default to random strings, which the provider rejects as ARNs.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-2:111122223333:log-group:/aws/vendedlogs/states/TEAM-AppStream-Controller-main"
    }
  }
  mock_resource "aws_sfn_state_machine" {
    defaults = {
      arn = "arn:aws:states:eu-west-2:111122223333:stateMachine:TEAM-AppStream-Controller-main"
    }
  }
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-west-2:111122223333:TEAM-AppStream-Controller-main-dlq"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/controller"
      key_id = "controller"
    }
  }
}
# Consumers run Terraform 1.9.3 and validate tests/ on init - keep to syntax it supports.

variables {
  requests_table_name = "requests-abc123-main"
  instance_arn        = "arn:aws:sso:::instance/ssoins-0123456789abcdef"
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "111122223333"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-2"
  }
}

override_data {
  target = data.aws_dynamodb_table.requests
  values = {
    arn        = "arn:aws:dynamodb:eu-west-2:111122223333:table/requests-abc123-main"
    stream_arn = "arn:aws:dynamodb:eu-west-2:111122223333:table/requests-abc123-main/stream/2026-01-01T00:00:00.000"
  }
}

override_data {
  target = data.aws_kms_alias.registry
  values = {
    target_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/registry"
  }
}

override_data {
  target = data.aws_kms_alias.ledger
  values = {
    target_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/ledger"
  }
}

# apply, not plan: the policies reference computed ARNs, mocked above.
run "safe_by_default" {
  command = apply

  assert {
    condition     = jsondecode(aws_sfn_state_machine.controller.definition).QueryLanguage == "JSONata"
    error_message = "The definition must render to valid JSON using JSONata."
  }

  assert {
    condition     = !strcontains(aws_sfn_state_machine.controller.definition, "$${")
    error_message = "Every template placeholder must be rendered."
  }

  assert {
    condition     = strcontains(aws_sfn_state_machine.controller.definition, "arn:aws:states:eu-west-2:111122223333:execution:TEAM-Schedule-SM-main:") && strcontains(aws_sfn_state_machine.controller.definition, "arn:aws:states:eu-west-2:111122223333:execution:TEAM-Revoke-SM-main:")
    error_message = "Sessions must be verified against TEAM's own Schedule and Revoke executions."
  }

  assert {
    condition     = strcontains(aws_sfn_state_machine.controller.definition, "aws-sdk:ssoadmin:listAccountAssignments") && strcontains(aws_sfn_state_machine.controller.definition, "'InstanceArn': 'arn:aws:sso:::instance/ssoins-0123456789abcdef'")
    error_message = "A session must only count while its TEAM account assignment exists, checked in the configured instance."
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.controller.definition).States.Start.Assign.dryRun == true
    error_message = "dry_run must default to true."
  }

  assert {
    condition     = aws_pipes_pipe.requests.desired_state == "STOPPED"
    error_message = "The pipe must be stopped by default, so a first apply reads nothing from the TEAM stream."
  }

  assert {
    condition     = aws_scheduler_schedule.sweep.state == "DISABLED"
    error_message = "The sweep must be disabled by default."
  }

  assert {
    condition     = jsondecode(one(aws_pipes_pipe.requests.source_parameters[0].filter_criteria[0].filter).pattern) == { eventName = ["MODIFY"], dynamodb = { NewImage = { status = { S = ["in progress", "ended", "revoked", "error"] } } } }
    error_message = "The pipe filter must pass only session start and stop statuses (tested as P1)."
  }

  assert {
    condition     = aws_pipes_pipe.requests.source_parameters[0].dynamodb_stream_parameters[0].batch_size == 1 && aws_pipes_pipe.requests.source_parameters[0].dynamodb_stream_parameters[0].starting_position == "LATEST"
    error_message = "The pipe must read one record at a time from the latest position."
  }

  assert {
    condition     = aws_sfn_state_machine.controller.tracing_configuration[0].enabled && aws_sfn_state_machine.controller.logging_configuration[0].level == "ALL" && aws_sfn_state_machine.controller.logging_configuration[0].include_execution_data
    error_message = "Tracing and full execution history logging must be on."
  }

  assert {
    condition     = aws_cloudwatch_log_group.controller.kms_key_id == aws_kms_key.controller.arn && aws_scheduler_schedule.sweep.kms_key_arn == aws_kms_key.controller.arn
    error_message = "Execution logs hold user ids, and both they and the schedule payload must use the module's CMK."
  }

  assert {
    condition     = one([for s in jsondecode(aws_kms_key_policy.controller.policy).Statement : s if s.Sid == "Allow CloudWatch Logs for this log group only"]).Condition == { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:eu-west-2:111122223333:log-group:/aws/vendedlogs/states/TEAM-AppStream-Controller-main" } }
    error_message = "CloudWatch Logs may only use the key for this log group."
  }

  assert {
    condition     = length([for s in jsondecode(aws_kms_key_policy.controller.policy).Statement : s if s.Sid == "Allow readers to decrypt the schedule payload"]) == 0
    error_message = "No reader statement may be rendered when reader_role_arns is empty."
  }
}

# Least privilege, asserted on the rendered policies.
run "least_privilege" {
  command = apply

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement :
      s.Condition == { StringEquals = { "aws:ResourceTag/team-appstream-managed" = "true" } }
      if length([for a in s.Action : a if strcontains(a, "ApplicationAssignment")]) > 0
    ])
    error_message = "Application assignment actions must be limited to applications tagged team-appstream-managed=true."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement : s if s.Sid == "ReadTeamAccountAssignments"]).Action == ["sso:ListAccountAssignments"] && one([for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement : s if s.Sid == "ReadTeamAccountAssignments"]).Resource == ["arn:aws:sso:::instance/ssoins-0123456789abcdef", "arn:aws:sso:::permissionSet/ssoins-0123456789abcdef/*", "arn:aws:sso:::account/*"]
    error_message = "Account assignments may only be listed, and only in the TEAM instance."
  }

  assert {
    condition     = length(flatten([for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement : [for a in s.Action : a if startswith(a, "sso:")]])) == 4
    error_message = "The controller's only IdC actions are the three tagged application assignment actions and ListAccountAssignments."
  }

  assert {
    condition     = length(flatten([for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement : [for a in s.Action : a if startswith(a, "states:")]])) == 2 && !strcontains(aws_iam_role_policy.state_machine.policy, "states:StartExecution")
    error_message = "The controller may only read TEAM executions, never start or stop them."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement :
      s.Action == ["dynamodb:Query"] && s.Resource == ["arn:aws:dynamodb:eu-west-2:111122223333:table/requests-abc123-main/index/byStatus"]
      if strcontains(jsonencode(s.Resource), "requests-")
    ])
    error_message = "The TEAM requests table must be read-only: Query on the byStatus index only."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement : s if s.Sid == "ReadRegistry"]).Action == ["dynamodb:GetItem", "dynamodb:Scan"]
    error_message = "The registry must be read-only."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.state_machine.policy).Statement : s if s.Sid == "UseTableKeysViaDynamoDB"]).Condition == { StringEquals = { "kms:ViaService" = "dynamodb.eu-west-2.amazonaws.com" } }
    error_message = "Table keys may only be used through DynamoDB."
  }

  assert {
    condition     = alltrue(flatten([for p in [aws_iam_role_policy.state_machine.policy, aws_iam_role_policy.pipe.policy, aws_iam_role_policy.scheduler.policy] : [for s in jsondecode(p).Statement : !contains(s.Resource, "*")]]))
    error_message = "Only the log delivery policy may use Resource \"*\"."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.state_machine_logs.policy).Statement[0].Action == ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"] && length(jsondecode(aws_iam_role_policy.state_machine_logs.policy).Statement) == 1
    error_message = "The Resource \"*\" statement must hold the log delivery actions only."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.pipe.policy).Statement : s if s.Sid == "StartController"]).Resource == [aws_sfn_state_machine.controller.arn] && one([for s in jsondecode(aws_iam_role_policy.scheduler.policy).Statement : s if s.Sid == "StartController"]).Resource == [aws_sfn_state_machine.controller.arn]
    error_message = "The pipe and scheduler may only start this state machine."
  }

}

run "enabled" {
  command = apply

  variables {
    dry_run       = false
    pipe_enabled  = true
    sweep_enabled = true
  }

  assert {
    condition     = aws_pipes_pipe.requests.desired_state == "RUNNING" && aws_scheduler_schedule.sweep.state == "ENABLED"
    error_message = "The pipe and sweep must start when enabled."
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.controller.definition).States.Start.Assign.dryRun == false
    error_message = "dry_run = false must reach the definition."
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.sweep.target[0].input) == { mode = "sweep" }
    error_message = "The schedule must start the sweep."
  }
}

run "plan_role_can_read_the_schedule" {
  command = apply

  variables {
    reader_role_arns = ["arn:aws:iam::111122223333:role/cc-pam-team-terragrunt-plan-role"]
  }

  assert {
    condition     = one([for s in jsondecode(aws_kms_key_policy.controller.policy).Statement : s if s.Sid == "Allow readers to decrypt the schedule payload"]).Principal.AWS == ["arn:aws:iam::111122223333:role/cc-pam-team-terragrunt-plan-role"]
    error_message = "Reader roles must be granted on the controller key."
  }

  assert {
    condition     = one([for s in jsondecode(aws_kms_key_policy.controller.policy).Statement : s if s.Sid == "Allow readers to decrypt the schedule payload"]).Action == ["kms:Decrypt", "kms:DescribeKey"]
    error_message = "Readers may only decrypt and describe the key."
  }
}

run "rejects_wrong_requests_table" {
  command = plan

  variables {
    requests_table_name = "TEAM-AppStream-Registry-main"
  }

  expect_failures = [var.requests_table_name]
}

run "rejects_wrong_instance_arn" {
  command = plan

  variables {
    instance_arn = "arn:aws:sso::217442266296:application/ssoins-0123456789abcdef/apl-0123456789abcdef"
  }

  expect_failures = [var.instance_arn]
}
