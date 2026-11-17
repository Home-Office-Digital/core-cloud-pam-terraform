output "state_machine_arn" {
  description = "ARN of the controller state machine, for manual Start execution tests"
  value       = aws_sfn_state_machine.controller.arn
}

output "alarms_topic_arn" {
  description = "ARN of the encrypted SNS topic both alarms notify, on alarm and on recovery"
  value       = aws_sns_topic.alarms.arn
}
