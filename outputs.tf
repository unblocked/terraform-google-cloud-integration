output "integration_configuration_json" {
  value = jsonencode({
    schema_version        = 1
    project_id            = var.project_id
    service_account_email = google_service_account.mcp.email
    mcp_endpoints = {
      for service in var.native_mcp_allowed_services : split(".", service)[0] => "https://${service}/mcp"
    }
    aws_workload_identity_provider = google_iam_workload_identity_pool_provider.mcp_aws[0].name
    aws_broker_role_arns = [
      for role_name in var.aws_account.role_names : "arn:aws:iam::${var.aws_account.account_id}:role/${role_name}"
    ]
    aws_external_account_credential = jsondecode(local.external_account_credential)
  })
  description = "Machine-readable configuration to provide to Unblocked after applying the module."
}
