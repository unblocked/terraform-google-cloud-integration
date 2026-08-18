locals {
  required_services = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  wif_resource_id = trimprefix(var.native_mcp_service_account_id, "gcp-")

  aws_provider_attribute_condition = format(
    "assertion.account == '%s' && (%s)",
    var.aws_account.account_id,
    join(" || ", [
      for role_name in var.aws_account.role_names : format(
        "assertion.arn.startsWith(%s)",
        jsonencode("arn:aws:sts::${var.aws_account.account_id}:assumed-role/${role_name}/")
      )
    ])
  )
}

resource "google_project_service" "required" {
  for_each = var.manage_required_services ? local.required_services : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "mcp" {
  for_each = var.native_mcp_allowed_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "mcp" {
  project      = var.project_id
  account_id   = var.native_mcp_service_account_id
  display_name = var.native_mcp_service_account_display_name

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "mcp_read_only" {
  for_each = var.native_mcp_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.mcp.email}"

  depends_on = [google_project_service.mcp]
}

resource "google_project_iam_member" "mcp_tool_user" {
  project = var.project_id
  role    = "roles/mcp.toolUser"
  member  = "serviceAccount:${google_service_account.mcp.email}"

  condition {
    title       = "configured-mcp-services-only"
    description = "Restrict MCP tool calls to the configured service allowlist."
    expression = join(" || ", [
      for service in var.native_mcp_allowed_services : "resource.service == '${service}'"
    ])
  }

  depends_on = [google_project_service.mcp]
}

resource "google_iam_workload_identity_pool" "mcp_aws" {
  count = 1

  project                   = var.project_id
  workload_identity_pool_id = "${local.wif_resource_id}-pool"
  display_name              = "Unblocked GCP MCP access"
  description               = "Federates approved Unblocked AWS workloads for access to Google Cloud MCP services"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "mcp_aws" {
  count = 1

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.mcp_aws[0].workload_identity_pool_id
  workload_identity_pool_provider_id = local.wif_resource_id
  display_name                       = "Unblocked GCP MCP access"
  description                        = "AWS account ${var.aws_account.account_id}; allowed broker roles: ${join(", ", var.aws_account.role_names)}"
  attribute_condition                = local.aws_provider_attribute_condition

  aws {
    account_id = var.aws_account.account_id
  }

  attribute_mapping = {
    "google.subject"    = "assertion.arn"
    "attribute.account" = "assertion.account"
  }

  depends_on = [google_iam_workload_identity_pool.mcp_aws]
}

resource "google_service_account_iam_member" "mcp_aws_workload_identity" {
  service_account_id = google_service_account.mcp.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.mcp_aws[0].name}/attribute.account/${var.aws_account.account_id}"
}
