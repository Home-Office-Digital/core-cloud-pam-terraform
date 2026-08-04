mock_provider "aws" {}

run "plan_secret" {
  command = plan

  variables {
    name        = "TEAM-IDC-APP/test"
    description = "TEAM app secret for tests"
    kms_key_id  = "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
    secret_data = {
      username = "team-user"
      password = "team-password"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.team_secret.name == "TEAM-IDC-APP/test"
    error_message = "Secret name should match the provided variable."
  }

  assert {
    condition     = aws_secretsmanager_secret.team_secret.kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
    error_message = "Secret should use the provided KMS key ARN."
  }

  assert {
    condition     = aws_secretsmanager_secret.team_secret.description == "TEAM app secret for tests"
    error_message = "Secret description should match the provided variable."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.team_secret.secret_string == jsonencode(var.secret_data)
    error_message = "Secret string should be the JSON-encoded secret_data map."
  }
}

run "plan_secret_with_rotated_value" {
  command = plan

  variables {
    name        = "TEAM-IDC-APP/test"
    description = "TEAM app secret for rotated test"
    kms_key_id  = "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
    secret_data = {
      username = "team-user-rotated"
      password = "team-password-rotated"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.team_secret.description == "TEAM app secret for rotated test"
    error_message = "Secret description should reflect the rotated test scenario."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.team_secret.secret_string == jsonencode(var.secret_data)
    error_message = "Secret version should render the rotated secret_data payload."
  }
}
