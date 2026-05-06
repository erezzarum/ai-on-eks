locals {
  aws_dranet_values = yamldecode(templatefile("${path.module}/helm-values/aws-dranet.yaml", {}))
}

resource "kubectl_manifest" "aws_dranet_yaml" {
  count = var.enable_aws_dranet && !var.enable_eks_auto_mode ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-addons/aws-dranet.yaml", {
    version          = var.aws_dranet_version
    user_values_yaml = indent(8, yamlencode(local.aws_dranet_values))
  })

  depends_on = [
    helm_release.argocd
  ]
}
