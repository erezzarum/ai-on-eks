variable "instance_type" {
  description = "EC2 instance type (e.g., p5.48xlarge, p5e.48xlarge, p5en.48xlarge, p6-b200.48xlarge, p6-b300.48xlarge, p6e-gb200.36xlarge)"
  type        = string

  validation {
    condition = contains([
      "p5.48xlarge",
      "p5e.48xlarge",
      "p5en.48xlarge",
      "p6-b200.48xlarge",
      "p6-b300.48xlarge",
      "p6e-gb200.36xlarge",
    ], var.instance_type)
    error_message = "Unsupported instance type. Must be one of: p5.48xlarge, p5e.48xlarge, p5en.48xlarge, p6-b200.48xlarge, p6-b300.48xlarge, p6e-gb200.36xlarge."
  }
}

variable "use_case" {
  description = "Use case number. 1 = IP Optimized (primary ENA + EFA-only on remaining cards), 2 = Bandwidth Optimized (primary ENA + combination of ENA and EFA-only to maximize IP and EFA bandwidth)."
  type        = number

  validation {
    condition     = var.use_case >= 1 && var.use_case <= 2
    error_message = "Use case must be 1 or 2."
  }
}

variable "subnet_id" {
  description = "Subnet ID for all network interfaces. Set to null for EKS-managed launch templates."
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to all network interfaces. Set to null for Karpenter output."
  type        = list(string)
  default     = null
}
