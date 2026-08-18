variable "project_id" {
  description = "GCP project in which to configure native Google Cloud MCP access."
  type        = string
}

variable "manage_required_services" {
  description = "Whether the module manages the IAM, IAM Credentials, and Security Token Service APIs."
  type        = bool
}

variable "native_mcp_service_account_id" {
  description = "Account ID for the native Google Cloud MCP service account and the basis of the derived WIF resource IDs."
  type        = string

  validation {
    condition = (
      length(trimprefix(var.native_mcp_service_account_id, "gcp-")) >= 4 &&
      length(trimprefix(var.native_mcp_service_account_id, "gcp-")) <= 27 &&
      !startswith(trimprefix(var.native_mcp_service_account_id, "gcp-"), "gcp-")
    )
    error_message = "The service-account ID, after removing one leading gcp- prefix, must produce a 4-27 character WIF ID that does not start with gcp-."
  }
}

variable "native_mcp_service_account_display_name" {
  description = "Display name for the native Google Cloud MCP service account."
  type        = string
}

variable "native_mcp_allowed_services" {
  description = "Google Cloud services whose native MCP tools may be called."
  type        = set(string)

  validation {
    condition     = length(var.native_mcp_allowed_services) > 0
    error_message = "At least one native MCP service must be allowed."
  }
}

variable "native_mcp_roles" {
  description = "Project roles granted to the native Google Cloud MCP service account."
  type        = set(string)
}

variable "aws_account" {
  description = "Unblocked AWS account and exact broker IAM role names allowed to use the MCP service account."
  type = object({
    account_id = string
    role_names = set(string)
  })

  validation {
    condition     = length(var.aws_account.role_names) > 0
    error_message = "The AWS account must contain at least one broker role name."
  }
}
