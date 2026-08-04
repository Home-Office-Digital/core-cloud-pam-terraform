# Terraform Module Testing

This repository now includes Terraform test files in each module under a `tests/` folder.

## Test layout

- `modules/cloudtrail/event_data_store/tests/event_data_store.tftest.hcl`
- `modules/dynamodb/team_policies/tests/team_policies.tftest.hcl`
- `modules/notifications/lambda/tests/lambda.tftest.hcl`
- `modules/secrets_manager/secret/tests/secret.tftest.hcl`

## Test approach

- Tests use `terraform test` with `mock_provider` blocks.
- Tests run `plan` only, so they do not create or destroy AWS resources.
- For modules with external lookups, tests use `override_data` to supply deterministic data.

## Prerequisites

- Terraform version that supports `.tftest.hcl` and `mock_provider` (Terraform 1.7+ recommended).
- Initialize each module before testing.

## Run tests

Run tests module by module:

```bash
cd modules/cloudtrail/event_data_store
terraform init
terraform test

cd ../../dynamodb/team_policies
terraform init
terraform test

cd ../../notifications/lambda
terraform init
terraform test

cd ../../secrets_manager/secret
terraform init
terraform test
```

Or run from repository root:

```bash
for module in \
  modules/cloudtrail/event_data_store \
  modules/dynamodb/team_policies \
  modules/notifications/lambda \
  modules/secrets_manager/secret
 do
  echo "Running tests in $module"
  terraform -chdir="$module" init -upgrade
  terraform -chdir="$module" test
done
```
