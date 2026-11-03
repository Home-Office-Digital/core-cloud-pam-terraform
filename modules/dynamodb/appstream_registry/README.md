# appstream_registry

Maps a TEAM target account to the IAM Identity Center (AppStream) application its sessions
are granted. The TEAM Grant and Revoke state machines look up `$.accountName`: a row means
in scope, no row means the session proceeds as normal. Adding a tenant is a row here, not a
change to the shared TEAM app.

- **AWS managed key, not a CMK.** Terraform reads these items on every plan, so a CMK would
  need `kms:Decrypt` on the plan role, which the shared baseline IAM module cannot scope.
- **Fails closed.** A missing table, missing row or renamed account means no AppStream; the
  TEAM session is unaffected.
- **Wrong-but-valid ARNs** are blocked at runtime: the state machine roles may only assign
  applications tagged `team-appstream-managed = true`.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.appstream_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table_item.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_applications"></a> [applications](#input\_applications) | Map of TEAM account name to the IdC application ARN its sessions are granted | `map(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Table name. Must match what the TEAM state machines build from the Amplify env, e.g. TEAM-AppStream-Registry-main | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the table | `map(string)` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
