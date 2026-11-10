# Grants and removes AppStream application assignments to match active TEAM sessions,
# without changing the TEAM app. See README.md.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  name       = "TEAM-AppStream-Controller-${var.env}"

  # TEAM resources, by the names TEAM's Amplify stack gives them.
  team_state_machines = { for k in ["Schedule", "Grant", "Revoke"] : k => "TEAM-${k}-SM-${var.team_env}" }
  registry_table      = "TEAM-AppStream-Registry-${var.env}"
  ledger_table        = "TEAM-AppStream-RefCount-${var.env}"

  execution_arn_prefix = "arn:aws:states:${local.region}:${local.account_id}:execution:"
  table_arn_prefix     = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/"

  definition = templatefile("${path.module}/definition.asl.json", {
    schedule_exec_prefix = "${local.execution_arn_prefix}${local.team_state_machines.Schedule}:"
    revoke_exec_prefix   = "${local.execution_arn_prefix}${local.team_state_machines.Revoke}:"
    requests_table       = var.requests_table_name
    registry_table       = local.registry_table
    ledger_table         = local.ledger_table
    dry_run              = var.dry_run
  })

  # Session start and stop statuses only. Everything else is ignored, and a match only
  # prompts a check: the state machine decides from TEAM's executions.
  pipe_filter = {
    eventName = ["MODIFY"]
    dynamodb = {
      NewImage = {
        status = { S = ["in progress", "ended", "revoked", "error"] }
      }
    }
  }
}

data "aws_dynamodb_table" "requests" {
  name = var.requests_table_name
}

data "aws_kms_alias" "registry" {
  name = "alias/${local.registry_table}"
}

data "aws_kms_alias" "ledger" {
  name = "alias/${local.ledger_table}"
}

# ---------------------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------------------

resource "aws_sfn_state_machine" "controller" {
  name       = local.name
  type       = "STANDARD"
  role_arn   = aws_iam_role.state_machine.arn
  definition = local.definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.controller.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = var.tags

  # Logging is checked against the role at create time, and the first run needs the rest.
  depends_on = [aws_iam_role_policy.state_machine, aws_iam_role_policy.state_machine_logs]
}

resource "aws_iam_role" "state_machine" {
  name = "${local.name}-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.name}" }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "state_machine" {
  name = "controller"
  role = aws_iam_role.state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadTeamExecutions"
        Effect   = "Allow"
        Action   = ["states:DescribeExecution", "states:GetExecutionHistory"]
        Resource = [for sm in values(local.team_state_machines) : "${local.execution_arn_prefix}${sm}:*"]
      },
      {
        Sid      = "QueryTeamRequestsByStatus"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = ["${data.aws_dynamodb_table.requests.arn}/index/byStatus"]
      },
      {
        Sid      = "ReadRegistry"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Scan"]
        Resource = ["${local.table_arn_prefix}${local.registry_table}"]
      },
      {
        Sid      = "ReadWriteLedger"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Scan"]
        Resource = ["${local.table_arn_prefix}${local.ledger_table}"]
      },
      {
        Sid      = "UseTableKeysViaDynamoDB"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [data.aws_kms_alias.registry.target_key_arn, data.aws_kms_alias.ledger.target_key_arn]
        Condition = {
          StringEquals = { "kms:ViaService" = "dynamodb.${local.region}.amazonaws.com" }
        }
      },
      {
        # Only applications deliberately tagged for TEAM. A wrong ARN in the registry
        # cannot touch any other application.
        Sid    = "ManageTaggedApplicationAssignments"
        Effect = "Allow"
        Action = [
          "sso:CreateApplicationAssignment",
          "sso:DeleteApplicationAssignment",
          "sso:DescribeApplicationAssignment",
        ]
        Resource = ["arn:aws:sso::*:application/*/*"]
        Condition = {
          StringEquals = { "aws:ResourceTag/team-appstream-managed" = "true" }
        }
      },
    ]
  })
}

# Step Functions log delivery actions have no resource-level support, so Resource is "*".
resource "aws_iam_role_policy" "state_machine_logs" {
  name = "execution-logs"
  role = aws_iam_role.state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DeliverExecutionLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups",
      ]
      Resource = ["*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "state_machine_xray" {
  role       = aws_iam_role.state_machine.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# ---------------------------------------------------------------------------------------
# Logs and the controller CMK
# ---------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "controller" {
  name              = "/aws/vendedlogs/states/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.controller.arn
  tags              = var.tags

  depends_on = [aws_kms_key_policy.controller]
}

resource "aws_kms_key" "controller" {
  description             = "CMK for the TEAM AppStream controller logs and schedule payload"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}

resource "aws_kms_alias" "controller" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.controller.key_id
}

resource "aws_kms_key_policy" "controller" {
  key_id = aws_kms_key.controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "Allow account administration of the key"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = aws_kms_key.controller.arn
      },
      {
        Sid       = "Allow CloudWatch Logs for this log group only"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = aws_kms_key.controller.arn
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/vendedlogs/states/${local.name}"
          }
        }
      },
      ],
      # Reading the schedule decrypts its payload with the caller's credentials. Granted here
      # because the baseline IAM module drops conditions and the key ARN is not known there.
      length(var.reader_role_arns) > 0 ? [{
        Sid       = "Allow readers to decrypt the schedule payload"
        Effect    = "Allow"
        Principal = { AWS = var.reader_role_arns }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = aws_kms_key.controller.arn
    }] : [])
  })
}

# ---------------------------------------------------------------------------------------
# Pipe: requests table stream -> state machine
# ---------------------------------------------------------------------------------------

resource "aws_pipes_pipe" "requests" {
  name          = local.name
  role_arn      = aws_iam_role.pipe.arn
  source        = data.aws_dynamodb_table.requests.stream_arn
  target        = aws_sfn_state_machine.controller.arn
  desired_state = var.pipe_enabled ? "RUNNING" : "STOPPED"

  source_parameters {
    dynamodb_stream_parameters {
      starting_position             = "LATEST"
      batch_size                    = 1
      maximum_retry_attempts        = 3
      maximum_record_age_in_seconds = 3600
      dead_letter_config {
        arn = aws_sqs_queue.dlq.arn
      }
    }
    filter_criteria {
      filter {
        pattern = jsonencode(local.pipe_filter)
      }
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy.pipe]
}

resource "aws_iam_role" "pipe" {
  name = "${local.name}-pipe"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pipes.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = "arn:aws:pipes:${local.region}:${local.account_id}:pipe/${local.name}"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "pipe" {
  name = "pipe"
  role = aws_iam_role.pipe.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadRequestsStream"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
        Resource = [data.aws_dynamodb_table.requests.stream_arn]
      },
      {
        Sid      = "StartController"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [aws_sfn_state_machine.controller.arn]
      },
      {
        Sid      = "DeadLetter"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.dlq.arn]
      },
    ]
  })
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-dlq"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  tags                      = var.tags
}

# ---------------------------------------------------------------------------------------
# Sweep: the safety net for missed, delayed or failed events
# ---------------------------------------------------------------------------------------

resource "aws_scheduler_schedule" "sweep" {
  name                = "${local.name}-sweep"
  schedule_expression = var.sweep_schedule
  state               = var.sweep_enabled ? "ENABLED" : "DISABLED"
  kms_key_arn         = aws_kms_key.controller.arn

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.controller.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ mode = "sweep" })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${local.name}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "scheduler"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartController"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [aws_sfn_state_machine.controller.arn]
      },
      {
        Sid      = "DecryptSchedulePayload"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.controller.arn]
      },
    ]
  })
}

# ---------------------------------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "executions_failed" {
  alarm_name          = "${local.name}-executions-failed"
  alarm_description   = "AppStream controller runs failed. The next sweep retries, but repeated failures leave AppStream out of step with TEAM sessions."
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.controller.arn }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${local.name}-dlq-not-empty"
  alarm_description   = "Stream records the pipe could not deliver. The sweep covers them, but the cause needs a look."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
  tags                = var.tags
}
