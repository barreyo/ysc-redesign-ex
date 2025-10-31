variable "environment" {
  description = "Environment name (e.g., 'sandbox', 'staging', 'production')"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment name must be lowercase alphanumeric and may contain hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for the S3 bucket"
  type        = string
  default     = "us-west-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the bucket name. If empty, defaults to 'ysc-media'. Final bucket name will be '{prefix}-{environment}'"
  type        = string
  default     = "ysc-media"
}

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins (restrict to your actual domains in production)"
  type        = list(string)
  default     = ["*"]

  validation {
    condition     = length(var.allowed_cors_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "lifecycle_noncurrent_days" {
  description = "Number of days before non-current versions are deleted (production only)"
  type        = number
  default     = 90
}

variable "lifecycle_transition_days" {
  description = "Number of days before objects transition to Glacier (production only)"
  type        = number
  default     = 90
}

variable "lifecycle_storage_class" {
  description = "Storage class to transition to (production only)"
  type        = string
  default     = "GLACIER"

  validation {
    condition     = contains(["GLACIER", "DEEP_ARCHIVE", "INTELLIGENT_TIERING"], var.lifecycle_storage_class)
    error_message = "Storage class must be one of: GLACIER, DEEP_ARCHIVE, INTELLIGENT_TIERING"
  }
}

