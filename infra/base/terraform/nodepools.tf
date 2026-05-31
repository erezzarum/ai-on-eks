locals {
  default_nodepools = {
    gpu                    = true
    neuron                 = true
    gpu-p6e-gb200-36xlarge = false
  }

  nodepools     = merge(local.default_nodepools, var.nodepools)
  node_iam_role = var.enable_eks_auto_mode ? module.eks.node_iam_role_name : module.karpenter[0].node_iam_role_name

  ec2nodeclass = templatefile("${path.module}/karpenter-resources/templates/${var.ami_family}_ec2nodeclass.tpl",
    {
      node_iam_role                       = local.node_iam_role
      cluster_name                        = module.eks.cluster_name
      enable_soci_snapshotter             = var.enable_soci_snapshotter
      soci_snapshotter_use_instance_store = var.soci_snapshotter_use_instance_store
      data_disk_snapshot_id               = var.bottlerocket_data_disk_snapshot_id
      max_user_namespaces                 = var.max_user_namespaces
    }
  )

  efa_instance_types = ["p5.48xlarge", "p5e.48xlarge", "p5en.48xlarge", "p6-b200.48xlarge", "p6-b300.48xlarge", "p6e-gb200.36xlarge"]
}

###############################################################################
# EFA Network Interfaces
#
# Generates network interface specifications for each EFA-capable instance type.
# Outputs are keyed by instance type (e.g., module.efa_network_interfaces["p5.48xlarge"]).
###############################################################################

module "efa_network_interfaces" {
  source   = "./modules/efa-networkinterfaces-generator"
  for_each = { for inst in local.efa_instance_types : inst => inst }

  instance_type      = each.value
  use_case           = 2
  security_group_ids = [module.eks.cluster_primary_security_group_id]
}

################################################################################
# NodePools & NodeClasses
################################################################################
data "kubectl_path_documents" "nodepools_manifests" {
  pattern = "${path.module}/karpenter-resources/${var.enable_eks_auto_mode ? "auto-mode" : "karpenter"}/*.yaml"
  vars = {
    node_iam_role             = local.node_iam_role
    cluster_name              = module.eks.cluster_name
    cluster_security_group_id = module.eks.cluster_primary_security_group_id
    ami_family                = var.ami_family
    ec2nodeclass              = local.ec2nodeclass
    efa_network_interfaces    = jsonencode({ for k, v in module.efa_network_interfaces : k => v.karpenter_network_interfaces_yaml })
  }
  depends_on = [
    module.karpenter,
    helm_release.karpenter,
    aws_ec2_tag.cluster_primary_security_group
  ]
}

# workaround terraform issue with attributes that cannot be determined ahead because of module dependencies
# https://github.com/gavinbunney/terraform-provider-kubectl/issues/58
data "kubectl_path_documents" "nodepools_manifests_dummy" {
  pattern = "${path.module}/karpenter-resources/${var.enable_eks_auto_mode ? "auto-mode" : "karpenter"}/*.yaml"
  vars = {
    node_iam_role             = ""
    cluster_name              = ""
    cluster_security_group_id = ""
    ami_family                = ""
    ec2nodeclass              = ""
    efa_network_interfaces    = jsonencode({ for inst in local.efa_instance_types : inst => "" })
  }
}

resource "kubectl_manifest" "nodepools_manifests" {
  for_each = {
    for key, value in data.kubectl_path_documents.nodepools_manifests_dummy.manifests :
    key => value if lookup(local.nodepools, element(split("/", key), length(split("/", key)) - 1), true)
  }

  yaml_body = data.kubectl_path_documents.nodepools_manifests.manifests[each.key]
  wait      = true
}
