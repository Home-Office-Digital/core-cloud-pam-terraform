# appstream_registry

Maps a TEAM target account to the IAM Identity Center (AppStream) application its sessions
are granted. The TEAM Grant and Revoke state machines look up `$.accountId`: a row means in
scope, no row means the session proceeds as normal. Adding a tenant is a row here, not a
change to the shared TEAM app.

- **Keyed on account ID.** TEAM keeps a client-supplied `accountName` when it cannot resolve
  one, whereas `accountId` is what eligibility and the account assignment use. Config still
  takes account **names**; they are resolved through Organizations, and a name that matches
  no active account, or more than one, fails the plan.
- **Own CMK**, matching `appstream_refcount`. Roles in `reader_role_arns` (e.g. the terragrunt
  plan role) get `kms:Decrypt` in the key policy, limited to calls via DynamoDB. That grant
  lives in the key policy because the baseline IAM module drops conditions.
- **Fails closed.** A missing table or row means no AppStream; the TEAM session is unaffected.
- **Wrong-but-valid ARNs** are blocked at runtime: the state machine roles may only assign
  applications tagged `team-appstream-managed = true`.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.appstream_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table_item.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_kms_alias.appstream_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.appstream_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key_policy.appstream_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.appstream_registry_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_applications"></a> [applications](#input\_applications) | Map of TEAM account name to the IdC application ARN its sessions are granted | `map(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Table name. Must match what the TEAM state machines build from the Amplify env, e.g. TEAM-AppStream-Registry-main | `string` | n/a | yes |
| <a name="input_reader_role_arns"></a> [reader\_role\_arns](#input\_reader\_role\_arns) | IAM role ARNs allowed to decrypt the table via DynamoDB without an IAM grant, e.g. the terragrunt plan role. Must already exist. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the table | `map(string)` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
