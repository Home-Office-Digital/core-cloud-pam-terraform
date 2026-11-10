variable "name" {
  description = "Name of the DynamoDB table. Must match the name the AppStream controller derives from its env, e.g. TEAM-AppStream-RefCount-main"
  type        = string

  # The controller (stepfunctions/appstream_controller) derives this name from its env.
  # Nothing else enforces that the two sides agree, and a
  # mismatch would fail silently: the UpdateItem calls would target a table that does
  # not exist, so no assignment would ever be reference-counted.
  validation {
    condition     = can(regex("^TEAM-AppStream-RefCount-[A-Za-z0-9-]+$", var.name))
    error_message = "name must be of the form TEAM-AppStream-RefCount-<env>, matching the name the AppStream controller derives from its env."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Whether to enable point-in-time recovery. The table is reconstructible by the reconciliation sweep, but losing it causes incorrect assign/unassign decisions until that sweep runs"
  type        = bool
  default     = true
}

variable "deletion_protection_enabled" {
  description = "Whether to enable deletion protection. Removing this table while sessions are active would strand AppStream assignments"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the table and its CMK"
  type        = map(string)
  default     = {}
}
