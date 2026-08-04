mock_provider "aws" {}
mock_provider "archive" {}

run "plan_notification_lambda" {
  command = plan

  variables {
    function_name          = "team-sns-handler-test"
    role_name              = "team-sns-handler-role-test"
    policy_name            = "team-sns-handler-policy-test"
    lambda_permission_sid  = "AllowExecutionFromSNSTest"
    sns_topic_name         = "team-notifications-test"
    source_file            = "./src/lambda_function.py"
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "111122223333"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.archive_file.lambda
    values = {
      output_base64sha256 = "dGVzdC1oYXNo"
    }
  }

  override_data {
    target = data.aws_sns_topic.team_notifications
    values = {
      arn = "arn:aws:sns:eu-west-2:111122223333:team-notifications-test"
    }
  }

  override_resource {
    target = aws_signer_signing_profile.lambda_signing
    values = {
      name = "lambdasigningprofile"
    }
  }

  assert {
    condition     = aws_lambda_function.team_sns_handler.runtime == "python3.13"
    error_message = "Lambda runtime should be python3.13."
  }

  assert {
    condition     = contains(aws_lambda_function.team_sns_handler.architectures, "arm64")
    error_message = "Lambda architecture should include arm64."
  }

  assert {
    condition     = aws_sqs_queue.lambda_dlq.sqs_managed_sse_enabled == true
    error_message = "Lambda DLQ should have SQS managed encryption enabled."
  }

  assert {
    condition     = aws_lambda_function.team_sns_handler.reserved_concurrent_executions == 5
    error_message = "Lambda reserved concurrency should be set to 5."
  }

  assert {
    condition     = aws_lambda_function.team_sns_handler.tracing_config[0].mode == "Active"
    error_message = "Lambda tracing mode should be Active."
  }

  assert {
    condition     = aws_lambda_permission.allow_sns.source_arn == "arn:aws:sns:eu-west-2:111122223333:team-notifications-test"
    error_message = "Lambda permission source ARN should target the configured SNS topic."
  }

  assert {
    condition     = aws_sns_topic_subscription.lambda.protocol == "lambda"
    error_message = "SNS subscription protocol should be lambda."
  }

  assert {
    condition     = aws_iam_role.lambda_execution.path == "/service-role/"
    error_message = "Lambda execution role path should be /service-role/."
  }
}
