variable "name" {
  description = "Table name. Must match the name the AppStream controller derives from its env, e.g. TEAM-AppStream-Registry-main"
  type        = string

  validation {
    condition     = can(regex("^TEAM-AppStream-Registry-[A-Za-z0-9-]+$", var.name))
    error_message = "name must be of the form TEAM-AppStream-Registry-<env>."
  }
}

variable "applications" {
  description = "Map of TEAM account name to the IdC application ARNs its sessions are granted. The first ARN is also written as applicationArn for controllers before 0.17.0."
  type        = map(list(string))

  validation {
    condition     = alltrue([for arns in values(var.applications) : length(arns) > 0 && length(distinct(arns)) == length(arns)])
    error_message = "Every account needs at least one application ARN, with no duplicates."
  }

  validation {
    # Mirrors the ApplicationArn pattern in the CreateApplicationAssignment API reference.
    condition     = alltrue([for arn in flatten(values(var.applications)) : can(regex("^arn:aws(-[a-z]{1,5}){0,3}:sso::[0-9]{12}:application/(sso)?ins-[a-zA-Z0-9.-]{16}/apl-[a-zA-Z0-9]{16}$", arn))])
    error_message = "Every value must be an IdC application ARN, with 16-character instance and application IDs."
  }
}

variable "reader_role_arns" {
  description = "IAM role ARNs allowed to decrypt the table via DynamoDB without an IAM grant, e.g. the terragrunt plan role. Must already exist."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the table"
  type        = map(string)
  default     = {}
}
