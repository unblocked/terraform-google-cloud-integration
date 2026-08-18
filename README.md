# Terraform Google Cloud integration

This module configures keyless access from approved AWS workloads to Google-hosted native MCP servers. It creates a Google service account, enables the configured Google Cloud APIs, grants project IAM roles, and establishes AWS Workload Identity Federation without service-account keys.

## Requirements

| Name | Version |
| --- | --- |
| Terraform | `>= 1.5.0` |
| Google provider | `>= 6.46.0` |

The identity applying this module must be allowed to enable Google Cloud APIs, create service accounts and Workload Identity Federation resources, and manage the relevant project IAM bindings.

## Providers

| Name | Source | Version |
| --- | --- | --- |
| `google` | `hashicorp/google` | `>= 6.46.0` |

The module inherits the caller's Google provider configuration. It does not configure credentials or a provider alias.

## Usage

Pin the module to a release tag when consuming it from GitHub:

```hcl
module "gcp_mcp" {
  source = "git::https://github.com/unblocked/terraform-google-cloud-integration.git?ref=v0.1.0"

  project_id               = "customer-project"
  manage_required_services = true

  native_mcp_service_account_id           = "unblocked-gcp-access"
  native_mcp_service_account_display_name = "Unblocked access to GCP MCP"

  native_mcp_allowed_services = [
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  native_mcp_roles = [
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/viewer",
  ]

  aws_account = {
    account_id = "UNBLOCKED_AWS_ACCOUNT_ID"
    role_names = [
      "UNBLOCKED_GCP_BROKER_ROLE_NAME",
    ]
  }
}
```

All inputs intentionally have no defaults. This makes the APIs, IAM permissions, resource names, and trusted AWS identities visible in the customer's Terraform configuration.

## Required Google Cloud APIs

The integration requires these foundational APIs:

| API | Purpose |
| --- | --- |
| `iam.googleapis.com` | Creates the service account, Workload Identity Pool, and AWS provider. |
| `iamcredentials.googleapis.com` | Generates short-lived access tokens for the Google service account. |
| `sts.googleapis.com` | Exchanges AWS credentials for Google federated tokens. |

Set `manage_required_services = true` for the normal self-contained installation. The module enables these APIs and internally waits for them before creating dependent IAM and WIF resources. The customer does not need to define separate `google_project_service` resources or add a module-level `depends_on` block.

```hcl
module "gcp_mcp" {
  source = "git::https://github.com/unblocked/terraform-google-cloud-integration.git?ref=v0.1.0"

  manage_required_services = true
  # Remaining inputs omitted from this example.
}
```

Set `manage_required_services = false` only when the same Terraform configuration already manages all three APIs. In that case, the caller owns API lifecycle and ordering and should make the dependency explicit:

```hcl
resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"
}

resource "google_project_service" "iamcredentials" {
  project = var.project_id
  service = "iamcredentials.googleapis.com"
}

resource "google_project_service" "sts" {
  project = var.project_id
  service = "sts.googleapis.com"
}

module "gcp_mcp" {
  source = "git::https://github.com/unblocked/terraform-google-cloud-integration.git?ref=v0.1.0"

  manage_required_services = false
  # Remaining inputs omitted from this example.

  depends_on = [
    google_project_service.iam,
    google_project_service.iamcredentials,
    google_project_service.sts,
  ]
}
```

The module sets `disable_on_destroy = false` for APIs it enables. Removing the module therefore stops managing those API resources without disabling APIs that another workload might use.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `project_id` | Google Cloud project in which to configure native MCP access. | `string` | n/a | yes |
| `manage_required_services` | Whether the module enables the IAM, IAM Credentials, and Security Token Service APIs. Use `false` only when the caller already manages them. | `bool` | n/a | yes |
| `native_mcp_service_account_id` | Account ID for the native MCP service account and the basis of the WIF resource IDs. After removing one leading `gcp-`, the value must be 4–27 characters and must not still start with `gcp-`. | `string` | n/a | yes |
| `native_mcp_service_account_display_name` | Human-readable display name for the native MCP service account. | `string` | n/a | yes |
| `native_mcp_allowed_services` | Google Cloud service hostnames whose native MCP tools may be called. The module enables these APIs and restricts `roles/mcp.toolUser` to this set. Must contain at least one service. | `set(string)` | n/a | yes |
| `native_mcp_roles` | Project IAM roles granted to the MCP service account for access to underlying Google Cloud data. May be empty, but MCP tools will only succeed when the account has the permissions they require. | `set(string)` | n/a | yes |
| `aws_account` | Trusted Unblocked AWS account ID and the non-empty set of exact broker role names allowed to federate. | `object({ account_id = string, role_names = set(string) })` | n/a | yes |

Although collection literals in examples use list syntax, Terraform converts them to the declared set types. Callers do not need to use `toset()`.

The module derives the WIF pool and provider IDs from `native_mcp_service_account_id`. For example, `unblocked-gcp-access` creates service account `unblocked-gcp-access`, pool `unblocked-gcp-access-pool`, and provider `unblocked-gcp-access`. Because Google reserves the `gcp-` prefix for WIF IDs, the module removes that prefix when deriving WIF names. Keep the service-account ID stable after the initial apply because changing it replaces these resources, which changes the `service_account_email` and `aws_workload_identity_provider` outputs and requires re-sending them to Unblocked.

## Outputs

| Name | Description |
| --- | --- |
| `service_account_email` | Native MCP service account email to provide to Unblocked. |
| `aws_workload_identity_provider` | WIF provider resource name (`projects/{number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}`) to provide to Unblocked. |

## Integration output

Terraform does not automatically promote a child module's outputs to the root module. Re-export the two identifiers from the customer's configuration:

```hcl
output "unblocked_service_account_email" {
  value       = module.gcp_mcp.service_account_email
  description = "Service account email to provide to Unblocked after onboarding."
}

output "unblocked_aws_workload_identity_provider" {
  value       = module.gcp_mcp.aws_workload_identity_provider
  description = "WIF provider resource name to provide to Unblocked after onboarding."
}
```

After applying, retrieve them with:

```shell
terraform output -raw unblocked_service_account_email
terraform output -raw unblocked_aws_workload_identity_provider
```

## Resources created

Depending on the inputs, the module creates:

- The configured Google Cloud API service resources.
- One Google service account for native MCP access.
- Project IAM bindings for `native_mcp_roles`.
- A conditional `roles/mcp.toolUser` binding restricted to `native_mcp_allowed_services`.
- One AWS Workload Identity Pool.
- One AWS WIF provider and service-account `roles/iam.workloadIdentityUser` binding for the configured AWS account.

## Security model

- Authentication uses short-lived AWS and Google credentials; the module does not create service-account keys.
- The AWS provider verifies the AWS account ID and permits only configured broker role names. Individual Unblocked services assume the broker role, so adding a service does not require a customer-side WIF change.
- `roles/mcp.toolUser` is conditioned on the configured Google Cloud service allowlist.
- `native_mcp_roles` controls which underlying Google Cloud resources and data the MCP service account can read.
- The module does not grant Google users local ADC impersonation access.
