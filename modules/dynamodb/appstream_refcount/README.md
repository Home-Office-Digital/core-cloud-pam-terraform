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

## A key-only row is not a held assignment

Deleting the last set member removes the **attribute**, not the **item**: DynamoDB leaves the
row behind with only its key attributes, and `UpdateItem` will
[create a row even where none existed](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_UpdateItem.html),
so a revoke with no prior grant also produces one.

**Consumers must therefore test `attribute_exists(activeRequestIds)`, not the presence of a
row.** This matters most for the reconciliation sweep: it converges in both directions, so
treating every row returned by a `Query` on `applicationArn` as a live reference would make it
*recreate* assignments for sessions that have already ended — standing access, which is the
thing the design exists to prevent. Row presence only tells you the pair was seen before.

## Two deliberate omissions

- **`activeRequestIds` is not declared** as an attribute. DynamoDB only requires key
  attributes in the schema. It must remain a **String Set**, not a List, because atomic
  `ADD`/`DELETE` update expressions are only available on sets; a List would force a
  read-modify-write and reintroduce the race this table exists to remove.
- **No TTL.** Because empty rows persist as tombstones, a TTL looks like a tidy way to reap
  them. But a TTL timestamp written at grant time can fire while the set is still non-empty —
  an extended session, or a second overlapping session — deleting a live counter and leaving
  the next revoke to see an empty set and drop an assignment another session is still using.
  Tombstone count is bounded by distinct `(application, principal)` pairs, so leave them.

The table `name` must match the name the state machines build from the Amplify `env`
parameter, for example `TEAM-AppStream-RefCount-main`.

## Encryption

The module creates its own customer managed key, matching the pattern used by
`cloudtrail/event_data_store` in this repo. There is no input for supplying a key: the
table is always encrypted with the CMK created here.

A CMK rather than the AWS managed `aws/dynamodb` key because `CKV_AWS_119` is active org-wide
and has not been exempted — unlike `CKV_AWS_28`, which is on the global skip list.

Two details carried over from fixing `CKV_AWS_356` in `cloudtrail/event_data_store`:

- The key policy is attached with a separate `aws_kms_key_policy`, not inline on
  `aws_kms_key`. Inline, the key depends on the policy document, so the document cannot
  reference the key's own ARN and `resources` would have to be `"*"`.
- The policy grants **account root** administration of the key. Without it the key would
  have no administrator once the policy is applied and could never be changed again, and
  AWS's policy lockout safety check rejects a key policy that does not grant root
  `kms:PutKeyPolicy`. DynamoDB needs no service statement of its own — it creates grants on
  the key on behalf of the calling principal.

The alias is derived from the table name (`alias/team-appstream-refcount-<env>`) rather than
fixed, so it cannot collide if the module is deployed more than once in an account.

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
| [aws_kms_alias.appstream_refcount](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.appstream_refcount](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key_policy.appstream_refcount](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.appstream_refcount_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deletion_protection_enabled"></a> [deletion\_protection\_enabled](#input\_deletion\_protection\_enabled) | Whether to enable deletion protection. Removing this table while sessions are active would strand AppStream assignments | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the DynamoDB table. Must match the name the TEAM state machines build from the Amplify env parameter, e.g. TEAM-AppStream-RefCount-main | `string` | n/a | yes |
| <a name="input_point_in_time_recovery_enabled"></a> [point\_in\_time\_recovery\_enabled](#input\_point\_in\_time\_recovery\_enabled) | Whether to enable point-in-time recovery. The table is reconstructible by the reconciliation sweep, but losing it causes incorrect assign/unassign decisions until that sweep runs | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the table and its CMK | `map(string)` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
