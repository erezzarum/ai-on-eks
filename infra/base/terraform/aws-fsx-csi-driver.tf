resource "aws_eks_addon" "aws_fsx_csi_driver" {
  count                       = var.enable_aws_fsx_csi_driver ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-fsx-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  pod_identity_association {
    role_arn        = module.aws_fsx_csi_driver_iam_role[0].arn
    service_account = "fsx-csi-controller-sa"
  }
  tags = local.tags
}

module "aws_fsx_csi_driver_iam_role" {
  count   = var.enable_aws_fsx_csi_driver ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.4"

  name            = "${local.name}-aws-fsx-csi"
  use_name_prefix = true

  trust_policy_permissions = {
    EKSPodIdentity = {
      principals = [{
        type = "Service"
        identifiers = [
          "pods.eks.amazonaws.com",
        ]
      }]
      actions = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
    }
  }

  policies = {
    AmazonFSxFullAccess = "arn:aws:iam::aws:policy/AmazonFSxFullAccess"
  }

  tags = local.tags
}
