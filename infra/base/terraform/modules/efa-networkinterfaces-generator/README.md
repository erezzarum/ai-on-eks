# EFA Network Interfaces Generator — Terraform Module

This Terraform module generates network interface specifications for EC2 P family GPU instance types with EFA support.

## Supported Instance Types

| Instance Type | Network Cards | Device Indices | Use Case 1 (IP Optimized) | Use Case 2 (Bandwidth Optimized) |
|---|---|---|---|---|
| `p5.48xlarge` | 32 (NCI 0-31) | 2 (DI 0-1) | 1 IP | 8 IPs |
| `p5e.48xlarge` | 32 (NCI 0-31) | 2 (DI 0-1) | 1 IP | 8 IPs |
| `p5en.48xlarge` | 16 (NCI 0-15) | 3 (DI 0-2) | 1 IP | 8 IPs |
| `p6-b200.48xlarge` | 8 (NCI 0-7) | 3 (DI 0-2) | 1 IP | 8 IPs |
| `p6-b300.48xlarge` | 17 (NCI 0-16) | 2 (DI 0-1) | 1 IP | 17 IPs |
| `p6e-gb200.36xlarge` | 17 (NCI 0-16) | 3 (DI 0-2) | 1 IP | 5 IPs |

## Terminology

- **NCI** (NetworkCardIndex): The physical network card on the instance.
- **DI** (DeviceIndex): The logical device slot on a given network card.
- **ENA** (`interface`): A regular Elastic Network Adapter — gets an IP address.
- **EFA-only** (`efa-only`): An Elastic Fabric Adapter used only for EFA traffic, no IP address assigned.

## Use Cases

- **Use case 1 — IP Optimized**: Primary network interface as ENA, EFA-only for the rest of network cards. Minimizes IP address consumption.
- **Use case 2 — Bandwidth Optimized**: Primary network interface as ENA, combination of EFA-only and ENA interfaces to maximize IP and EFA network bandwidth.

## Usage

### Basic — Get network interface specs

```hcl
module "efa_interfaces" {
  source = "./modules/efa-networkinterfaces-generator"

  instance_type      = "p5.48xlarge"
  use_case           = 1
  subnet_id          = "subnet-0123456789abcdef0"
  security_group_ids = ["sg-0123456789abcdef0"]
}
```

### With aws_launch_template

```hcl
module "efa_interfaces" {
  source = "./modules/efa-networkinterfaces-generator"

  instance_type      = "p5en.48xlarge"
  use_case           = 2
  subnet_id          = "subnet-abc123"
  security_group_ids = ["sg-abc123", "sg-def456"]
}

resource "aws_launch_template" "gpu" {
  name_prefix   = "gpu-efa-"
  instance_type = module.efa_interfaces.instance_type

  dynamic "network_interfaces" {
    for_each = module.efa_interfaces.launch_template_network_interfaces
    content {
      associate_public_ip_address = network_interfaces.value.associate_public_ip_address
      delete_on_termination       = network_interfaces.value.delete_on_termination
      description                 = network_interfaces.value.description
      security_groups             = network_interfaces.value.security_groups
      subnet_id                   = network_interfaces.value.subnet_id
      network_card_index          = network_interfaces.value.network_card_index
      device_index                = network_interfaces.value.device_index
      interface_type              = network_interfaces.value.interface_type
    }
  }
}
```

### EKS Launch Template (no subnet — managed by EKS)

```hcl
module "efa_interfaces" {
  source = "./modules/efa-networkinterfaces-generator"

  instance_type      = "p5.48xlarge"
  use_case           = 1
  security_group_ids = ["sg-abc123"]
}

resource "aws_launch_template" "eks_gpu" {
  name_prefix = "eks-gpu-efa-"

  dynamic "network_interfaces" {
    for_each = module.efa_interfaces.eks_launch_template_network_interfaces
    content {
      associate_public_ip_address = network_interfaces.value.associate_public_ip_address
      delete_on_termination       = network_interfaces.value.delete_on_termination
      description                 = network_interfaces.value.description
      security_groups             = network_interfaces.value.security_groups
      network_card_index          = network_interfaces.value.network_card_index
      device_index                = network_interfaces.value.device_index
      interface_type              = network_interfaces.value.interface_type
    }
  }
}
```

### Karpenter EC2NodeClass

Use the `karpenter_network_interfaces` output to populate `spec.networkInterfaces` in a Karpenter `EC2NodeClass`. No `subnet_id` or `security_group_ids` are needed — Karpenter manages those via its own `spec.subnetSelectorTerms` and `spec.securityGroupSelectorTerms`.

```hcl
module "efa_interfaces" {
  source = "./modules/efa-networkinterfaces-generator"

  instance_type = "p5en.48xlarge"
  use_case      = 1
}

resource "kubernetes_manifest" "ec2_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "gpu-efa"
    }
    spec = {
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = "my-cluster" }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = "my-cluster" }
      }]
      networkInterfaces = module.efa_interfaces.karpenter_network_interfaces
    }
  }
}
```

Alternatively, if you manage Karpenter manifests outside of Terraform (e.g., via Helm or kubectl), use the `karpenter_network_interfaces_yaml` output to get a ready-to-paste YAML snippet:

```hcl
output "karpenter_yaml" {
  value = module.efa_interfaces.karpenter_network_interfaces_yaml
}
```

Which produces:

```yaml
networkInterfaces:
  - networkCardIndex: 0
    deviceIndex: 0
    interfaceType: "interface"
  - networkCardIndex: 0
    deviceIndex: 1
    interfaceType: "efa-only"
  - networkCardIndex: 1
    deviceIndex: 1
    interfaceType: "efa-only"
  # ... remaining interfaces
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `instance_type` | EC2 instance type | `string` | — | yes |
| `use_case` | Use case number (1 = IP Optimized, 2 = Bandwidth Optimized) | `number` | — | yes |
| `subnet_id` | Subnet ID for interfaces | `string` | `null` | no |
| `security_group_ids` | List of security group IDs | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| `network_interfaces` | Raw list of specs (network_card_index, device_index, interface_type) |
| `launch_template_network_interfaces` | Full interface blocks for `aws_launch_template` |
| `eks_launch_template_network_interfaces` | Interface blocks for EKS (no subnet_id) |
| `karpenter_network_interfaces` | Structured list for Karpenter `EC2NodeClass spec.networkInterfaces` |
| `karpenter_network_interfaces_yaml` | Pre-rendered YAML snippet for Karpenter |
| `instance_type` | Pass-through of selected instance type |
| `use_case` | Pass-through of selected use case |
