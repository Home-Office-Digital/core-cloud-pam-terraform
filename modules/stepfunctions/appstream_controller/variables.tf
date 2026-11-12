variable "env" {
  description = "Suffix shared with the registry and ref-count tables, e.g. main for TEAM-AppStream-Registry-main"
  type        = string
  default     = "main"
  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.env))
    error_message = "env may only contain letters, digits and hyphens."
  }
}

variable "team_env" {
  description = "Amplify env of the TEAM app, used to find its state machines, e.g. main for TEAM-Grant-SM-main"
  type        = string
  default     = "main"
  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.team_env))
    error_message = "team_env may only contain letters, digits and hyphens."
  }
}

variable "requests_table_name" {
  description = "TEAM requests table, e.g. requests-<appsync api id>-main. Its stream drives the pipe."
  type        = string
  validation {
    condition     = can(regex("^requests-[a-z0-9]+-[A-Za-z0-9-]+$", var.requests_table_name))
    error_message = "requests_table_name must be TEAM's Amplify requests table, of the form requests-<api id>-<env>."
  }
}

variable "instance_arn" {
  description = "IAM Identity Center instance TEAM grants in, e.g. arn:aws:sso:::instance/ssoins-0123456789abcdef. Used to check a session's account assignment still exists."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sso:::instance/ssoins-[a-zA-Z0-9-.]{16}$", var.instance_arn))
    error_message = "instance_arn must be an IAM Identity Center instance ARN, arn:aws:sso:::instance/ssoins-<16 characters>."
  }
}

variable "dry_run" {
  description = "Report intended actions without creating or deleting assignments or writing the ledger"
  type        = bool
  default     = true
}

variable "pipe_enabled" {
  description = "Start the pipe. Off by default so a first apply reads nothing from the TEAM stream."
  type        = bool
  default     = false
}

variable "sweep_enabled" {
  description = "Enable the scheduled sweep"
  type        = bool
  default     = false
}

variable "sweep_schedule" {
  description = "Schedule expression for the sweep"
  type        = string
  default     = "rate(5 minutes)"
}

variable "alarm_actions" {
  description = "ARNs notified when an alarm changes state, e.g. an SNS topic"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Retention for the execution log group"
  type        = number
  default     = 365
}

variable "reader_role_arns" {
  description = "IAM role ARNs allowed to decrypt the schedule payload, e.g. the terragrunt plan role, which reads it on refresh. Must already exist."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
