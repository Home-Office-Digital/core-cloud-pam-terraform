# appstream_controller

Gives a user an AppStream (IAM Identity Center application) assignment while they have an
active TEAM session on a registry account, and removes it when their last one ends. It makes
no changes to the TEAM app.

```
TEAM requests table stream ──▶ Pipe (status became in progress / ended / revoked / error)
                                  │
EventBridge Scheduler (sweep) ────┤
                                  ▼
                         Controller state machine
          1. Verify each session against TEAM's own executions
          2. Registry: accountId → application   (no row → nothing to do)
          3. Ledger (appstream_refcount): active request ids, owned or preexisting
          4. Create or delete the USER assignment to match
```

- **TEAM's executions decide, not the table.** A requester can edit their own request's
  `status` through TEAM's API, so a status change only prompts a check. A session counts as
  active only if its Schedule run started a Grant run that is RUNNING and in its session
  `Wait`, with no early-revoke run named after the request. `userId` and `accountId` come
  from the Grant run input.
- **Recomputed, not counted.** Every run works out the full set of active sessions for the
  user and application, so delayed, duplicated or out-of-order events cannot leave the
  assignment wrong. Before removing an assignment it re-checks once.
- **Only removes what it created.** An assignment that already existed is recorded as
  `preexisting` and never deleted. Ownership is written before a create and released only
  after a delete; every ledger write is conditional on `rev`.
- **Fails closed.** A missing execution, registry row or matching user means no AppStream.
  A failure never affects the TEAM session.
- **Least privilege.** Read-only on TEAM's executions and the `byStatus` index of the
  requests table. Application assignments only on applications tagged
  `team-appstream-managed = true`.
- **Safe first apply.** `dry_run`, a stopped pipe and a disabled sweep are the defaults.
  A dry run reports the intended `action` for each target and changes nothing.

Manual test: start an execution with `{"requestId": "<TEAM request id>"}`, or
`{"mode": "sweep"}`.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.dlq_not_empty](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.executions_failed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.pipe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.state_machine](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.pipe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.state_machine](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.state_machine_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.state_machine_xray](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key_policy.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_pipes_pipe.requests](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/pipes_pipe) | resource |
| [aws_scheduler_schedule.sweep](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_sfn_state_machine.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_dynamodb_table.requests](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/dynamodb_table) | data source |
| [aws_kms_alias.ledger](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |
| [aws_kms_alias.registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | ARNs notified when an alarm changes state, e.g. an SNS topic | `list(string)` | `[]` | no |
| <a name="input_dry_run"></a> [dry\_run](#input\_dry\_run) | Report intended actions without creating or deleting assignments or writing the ledger | `bool` | `true` | no |
| <a name="input_env"></a> [env](#input\_env) | Suffix shared with the registry and ref-count tables, e.g. main for TEAM-AppStream-Registry-main | `string` | `"main"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention for the execution log group | `number` | `365` | no |
| <a name="input_pipe_enabled"></a> [pipe\_enabled](#input\_pipe\_enabled) | Start the pipe. Off by default so a first apply reads nothing from the TEAM stream. | `bool` | `false` | no |
| <a name="input_requests_table_name"></a> [requests\_table\_name](#input\_requests\_table\_name) | TEAM requests table, e.g. requests-<appsync api id>-main. Its stream drives the pipe. | `string` | n/a | yes |
| <a name="input_sweep_enabled"></a> [sweep\_enabled](#input\_sweep\_enabled) | Enable the scheduled sweep | `bool` | `false` | no |
| <a name="input_sweep_schedule"></a> [sweep\_schedule](#input\_sweep\_schedule) | Schedule expression for the sweep | `string` | `"rate(5 minutes)"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_team_env"></a> [team\_env](#input\_team\_env) | Amplify env of the TEAM app, used to find its state machines, e.g. main for TEAM-Grant-SM-main | `string` | `"main"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_state_machine_arn"></a> [state\_machine\_arn](#output\_state\_machine\_arn) | ARN of the controller state machine, for manual Start execution tests |
<!-- END_TF_DOCS -->
