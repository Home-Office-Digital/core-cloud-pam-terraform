mock_provider "aws" {}

run "plan_event_data_store" {
  command = plan

  variables {
    name                 = "team-event-data-store-test"
    organization_enabled = true
    retention_period     = 365
    tags = {
      Environment = "test"
      ManagedBy   = "terraform-test"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.cloudtrail_kms
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_kms_key.cloudtrail_eds
    values = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/test-key-id"
      key_id = "test-key-id"
    }
  }

  assert {
    condition     = aws_cloudtrail_event_data_store.team_data_store.termination_protection_enabled == true
    error_message = "Event Data Store must enable termination protection."
  }

  assert {
    condition     = aws_cloudtrail_event_data_store.team_data_store.name == "team-event-data-store-test"
    error_message = "Event Data Store name should match the provided variable."
  }

  assert {
    condition     = aws_cloudtrail_event_data_store.team_data_store.organization_enabled == true
    error_message = "Organization-wide collection should be enabled in this scenario."
  }

  assert {
    condition     = aws_cloudtrail_event_data_store.team_data_store.retention_period == 365
    error_message = "Retention period should match the provided variable."
  }

  assert {
    condition     = aws_kms_key.cloudtrail_eds.enable_key_rotation == true
    error_message = "KMS key rotation should be enabled."
  }

  assert {
    condition     = aws_kms_alias.cloudtrail_eds.name == "alias/cloudtrail-event-data-store"
    error_message = "KMS alias should use the expected name."
  }
}

run "plan_event_data_store_org_disabled" {
  command = plan

  variables {
    name                 = "team-event-data-store-minimal"
    organization_enabled = false
    retention_period     = 30
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform-test"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.cloudtrail_kms
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_kms_key.cloudtrail_eds
    values = {
      arn    = "arn:aws:kms:eu-west-2:111122223333:key/test-key-id"
      key_id = "test-key-id"
    }
  }

  assert {
    condition     = aws_cloudtrail_event_data_store.team_data_store.organization_enabled == false
    error_message = "Organization collection should be disabled in this scenario."
  }

  assert {
    condition     = aws_cloudtrail_event_data_store.team_data_store.retention_period == 30
    error_message = "Retention period should be 30 days in this scenario."
  }
}
