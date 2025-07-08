resource "kubectl_manifest" "ai_ml_observability_yaml" {
  count     = var.enable_ai_ml_observability_stack ? 1 : 0
  yaml_body = file("${path.module}/argocd-addons/ai-ml-observability.yaml")

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "aibrix_dependency_yaml" {
  count     = var.enable_aibrix_stack ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-addons/aibrix-dependency.yaml", { aibrix_version = var.aibrix_stack_version })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "aibrix_core_yaml" {
  count     = var.enable_aibrix_stack ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-addons/aibrix-core.yaml", { aibrix_version = var.aibrix_stack_version })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "nvidia_nim_yaml" {
  count     = var.enable_nvidia_nim_stack ? 1 : 0
  yaml_body = file("${path.module}/argocd-addons/nvidia-nim-operator.yaml")

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "nvidia_dcgm_helm" {
  yaml_body = templatefile("${path.module}/argocd-addons/nvidia-dcgm-helm.yaml", { service_monitor_enabled = var.enable_ai_ml_observability_stack })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "kai_scheduler_helm" {
  count = var.enable_kai_scheduler ? 1 : 0
  yaml_body = templatefile("${path.module}/argocd-addons/kai-scheduler.yaml", {
    kai_scheduler_version     = var.kai_scheduler_version,
    kai_scheduler_autoscaling = var.kai_scheduler_cluster_autoscaling,
    kai_scheduler_gpusharing  = var.kai_scheduler_gpusharing
  })

  depends_on = [
    module.eks_blueprints_addons
  ]
}
