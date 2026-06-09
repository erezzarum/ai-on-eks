output "network_interfaces" {
  description = "List of network interface specifications sorted by (network_card_index, device_index). Each element contains: network_card_index, device_index, interface_type."
  value       = local.sorted_network_interfaces
}

output "launch_template_network_interfaces" {
  description = "Network interface blocks ready for use in aws_launch_template resource. Includes subnet_id and security_groups when provided."
  value = [
    for idx, spec in local.sorted_network_interfaces : {
      associate_public_ip_address = false
      delete_on_termination       = true
      description                 = "${spec.interface_type} - Network Interface ${spec.network_card_index}"
      security_groups             = var.security_group_ids
      subnet_id                   = var.subnet_id
      network_card_index          = spec.network_card_index
      device_index                = spec.device_index
      interface_type              = spec.interface_type
    }
  ]
}

output "eks_launch_template_network_interfaces" {
  description = "Network interface blocks for EKS launch templates (no subnet_id — managed by EKS). Requires security_group_ids."
  value = [
    for idx, spec in local.sorted_network_interfaces : {
      associate_public_ip_address = false
      delete_on_termination       = true
      description                 = "${spec.interface_type} - Network Interface ${spec.network_card_index}"
      security_groups             = var.security_group_ids
      network_card_index          = spec.network_card_index
      device_index                = spec.device_index
      interface_type              = spec.interface_type
    }
  ]
}

output "karpenter_network_interfaces" {
  description = "Network interface specs for Karpenter EC2NodeClass spec.networkInterfaces. Only includes networkCardIndex, deviceIndex, and interfaceType (no subnet or security groups — managed by Karpenter)."
  value = [
    for spec in local.sorted_network_interfaces : {
      networkCardIndex = spec.network_card_index
      deviceIndex      = spec.device_index
      interfaceType    = spec.interface_type
    }
  ]
}

output "karpenter_network_interfaces_yaml" {
  description = "Pre-rendered YAML snippet for Karpenter EC2NodeClass spec.networkInterfaces, matching the Python script's karpenter output format."
  value = join("\n", concat(
    ["networkInterfaces:"],
    flatten([
      for spec in local.sorted_network_interfaces : [
        "  - networkCardIndex: ${spec.network_card_index}",
        "    deviceIndex: ${spec.device_index}",
        "    interfaceType: \"${spec.interface_type}\"",
      ]
    ])
  ))
}

output "instance_type" {
  description = "The selected instance type (pass-through for convenience)."
  value       = var.instance_type
}

output "use_case" {
  description = "The selected use case number (pass-through for convenience)."
  value       = var.use_case
}
