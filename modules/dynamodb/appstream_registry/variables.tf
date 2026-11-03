variable "name" {
  description = "Table name. Must match what the TEAM state machines build from the Amplify env, e.g. TEAM-AppStream-Registry-main"
  type        = string

  validation {
    condition     = can(regex("^TEAM-AppStream-Registry-[A-Za-z0-9-]+$", var.name))
    error_message = "name must be of the form TEAM-AppStream-Registry-<env>."
  }
}

variable "applications" {
  description = "Map of TEAM account name to the IdC application ARN its sessions are granted"
  type        = map(string)

  validation {
    # Mirrors the ApplicationArn pattern in the CreateApplicationAssignment API reference.
    condition     = alltrue([for arn in values(var.applications) : can(regex("^arn:aws(-[a-z]{1,5}){0,3}:sso::[0-9]{12}:application/(sso)?ins-[a-zA-Z0-9.-]{16}/apl-[a-zA-Z0-9]{16}$", arn))])
    error_message = "Every value must be an IdC application ARN, with 16-character instance and application IDs."
  }
}

variable "tags" {
  description = "Tags to apply to the table"
  type        = map(string)
  default     = {}
}
