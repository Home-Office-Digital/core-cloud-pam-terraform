# appstream_registry

Maps a TEAM target account to the IAM Identity Center (AppStream) application a session for
that account should be granted. The TEAM Grant and Revoke state machines look up
`$.accountName` here:

- **Row found** — the session is in scope; its `applicationArn` is assigned for the life of
  the session, reference-counted in `appstream_refcount`.
- **No row** — the session proceeds exactly as before, with no AppStream.

Adding a tenant is a new entry in `applications`, not a change to the shared TEAM app. That
matters because `core-cloud-pam-team-app` is synced from upstream and every line there is
permanent patch surface.

## Encryption — deliberately not a CMK

Unlike `appstream_refcount`, this table uses the AWS managed key. Terraform reads these items
on every plan, so a customer managed key would need `kms:Decrypt` on the read-only plan role.
The shared `iam-role-with-oidc` module in `core-cloud-account-baseline` drops statement
conditions, so that permission could not be limited with `kms:ViaService` and would decrypt
any IAM-delegating key in the account. The table holds account names and application ARNs,
nothing sensitive. `CKV_AWS_119` is skipped inline with that reason; it is INFO severity.

## Failure modes

Every failure here fails closed. A missing table, a missing row or a renamed account means
no AppStream for that session, and the TEAM session itself carries on. A **valid ARN for the
wrong application** is the one case it cannot catch — `APC Live` and `APC Prod Live` differ
by one word and `PAM Live` serves every tenant. That is guarded at runtime instead: the state
machine roles may only assign applications tagged `team-appstream-managed = true`.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.appstream_registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table_item.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_applications"></a> [applications](#input\_applications) | Map of TEAM target account name (as carried in the TEAM payload's accountName) to the IdC application ARN a session for that account should be assigned. | `map(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the DynamoDB table. Must match the name the TEAM state machines build from the Amplify env parameter, e.g. TEAM-AppStream-Registry-main | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the table | `map(string)` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
