variable "name" {
  description = "Name of the DynamoDB table. Must match the name the TEAM state machines build from the Amplify env parameter, e.g. TEAM-AppStream-Registry-main"
  type        = string

  # The state machines build this name with Fn::Sub on the Amplify env parameter. A mismatch
  # fails closed - every lookup misses, so nobody gets AppStream - but silently.
  validation {
    condition     = can(regex("^TEAM-AppStream-Registry-[A-Za-z0-9-]+$", var.name))
    error_message = "name must be of the form TEAM-AppStream-Registry-<env>, matching the name the TEAM state machines construct from the Amplify env parameter."
  }
}

variable "applications" {
  description = "Map of TEAM target account name (as carried in the TEAM payload's accountName) to the IdC application ARN a session for that account should be assigned."
  type        = map(string)

  # Application names in this estate differ by one word (APC Live / APC Prod Live) and
  # PAM Live serves every tenant, so a malformed value must fail the plan rather than be
  # written. A valid ARN for the wrong application still passes this - that is caught at
  # runtime by the aws:ResourceTag condition on the state machine role.
  validation {
    condition     = alltrue([for arn in values(var.applications) : can(regex("^arn:aws:sso::[0-9]{12}:application/ssoins-[0-9a-f]+/apl-[0-9a-f]+$", arn))])
    error_message = "Every value must be an IdC application ARN of the form arn:aws:sso::<account>:application/ssoins-<id>/apl-<id>."
  }
}

variable "tags" {
  description = "Tags to apply to the table"
  type        = map(string)
  default     = {}
}
