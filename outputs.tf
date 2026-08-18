output "service_account_email" {
  value       = google_service_account.mcp.email
  description = "Native MCP service account email to provide to Unblocked."
}

output "aws_workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.mcp_aws[0].name
  description = "WIF provider resource name (projects/{number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}) to provide to Unblocked."
}
