# appstream_refcount

Reference-count table for ephemeral AppStream (IAM Identity Center application)
assignments driven by the TEAM session lifecycle.

An IdC application assignment is identified only by `(application ARN, principal id,
principal type)` — it has no account, session or request dimension. Two overlapping TEAM
sessions for the same user therefore share a single assignment, so deleting it when the
first session ends would cut off the second, still-active session.

The TEAM Grant and Revoke state machines keep the set of active request ids for each
`(application, principal)` in this table, and only remove the assignment once that set is
empty:

| State machine | Operation |
|---|---|
| Grant | `UpdateItem` `ADD activeRequestIds :id` → `createApplicationAssignment` |
| Revoke | `UpdateItem` `DELETE activeRequestIds :id` with `ReturnValues: UPDATED_NEW` → `Choice` on whether the attribute is now absent → `deleteApplicationAssignment` |

DynamoDB removes a set attribute entirely when its last element is deleted, so "the set is
empty" is expressible in Step Functions as an `IsPresent: false` check — no Lambda and no
arithmetic.

Two deliberate omissions:

- **`activeRequestIds` is not declared** as an attribute. DynamoDB only requires key
  attributes in the schema. It must remain a **String Set**, not a List, because atomic
  `ADD`/`DELETE` update expressions are only available on sets; a List would force a
  read-modify-write and reintroduce the race this table exists to remove.
- **No TTL.** Entries disappear when their set empties. A TTL could silently expire a
  counter still holding a live assignment open.

The table `name` must match the name the state machines build from the Amplify `env`
parameter, for example `TEAM-AppStream-RefCount-main`.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.appstream_refcount](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deletion_protection_enabled"></a> [deletion\_protection\_enabled](#input\_deletion\_protection\_enabled) | Whether to enable deletion protection. Removing this table while sessions are active would strand AppStream assignments | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt the table. Leave null to use the AWS managed aws/dynamodb key | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the DynamoDB table. Must match the name the TEAM state machines build from the Amplify env parameter, e.g. TEAM-AppStream-RefCount-main | `string` | n/a | yes |
| <a name="input_point_in_time_recovery_enabled"></a> [point\_in\_time\_recovery\_enabled](#input\_point\_in\_time\_recovery\_enabled) | Whether to enable point-in-time recovery. The table is reconstructible by the reconciliation sweep, but losing it causes incorrect assign/unassign decisions until that sweep runs | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the table | `map(string)` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
