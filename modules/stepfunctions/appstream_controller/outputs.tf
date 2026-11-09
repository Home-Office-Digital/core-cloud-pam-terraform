output "state_machine_arn" {
  description = "ARN of the controller state machine, for manual Start execution tests"
  value       = aws_sfn_state_machine.controller.arn
}
