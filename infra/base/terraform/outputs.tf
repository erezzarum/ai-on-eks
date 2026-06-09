output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.name}"
}

# output "grafana_secret_name" {
#   description = "The name of the secret containing the Grafana admin password."
#   value       = var.enable_kube_prometheus_stack ? aws_secretsmanager_secret.grafana[0].name : null
# }

output "deployment_name" {
  description = "Deployment name"
  value       = var.name
}

output "fsx_s3_bucket_name" {
  description = "Name of the S3 bucket for FSx"
  value       = var.deploy_fsx_volume ? module.fsx_s3_bucket[0].s3_bucket_id : null
}

# S3 Model Storage Outputs - Only output values when feature is enabled
output "s3_models_buckets_name" {
  description = "Name of the S3 models buckets"
  value       = var.enable_s3_models_storage ? flatten([concat([local.s3_models_bucket_name], var.s3_models_additional_buckets)]) : null
}

output "s3_models_sync_sa" {
  description = "Name of the model sync service account"
  value       = var.enable_s3_models_storage ? var.s3_models_sync_sa : null
}

output "s3_models_inference_sa" {
  description = "Name of the model inference service account"
  value       = var.enable_s3_models_storage ? var.s3_models_inference_sa : null
}

output "s3_models_sync_sa_namespace" {
  description = "Namespace for model sync service account"
  value       = var.enable_s3_models_storage ? var.s3_models_sync_sa_namespace : null
}

output "s3_models_inference_sa_namespace" {
  description = "Namespace for model inference service account"
  value       = var.enable_s3_models_storage ? var.s3_models_inference_sa_namespace : null
}

output "karpenter_node_iam_role" {
  description = "Karpenter Node IAM role"
  value       = var.enable_eks_auto_mode ? module.eks.node_iam_role_name : module.karpenter[0].node_iam_role_name
}

output "secondary_subnet_by_az" {
  description = "Map of secondary subnet ids by AZ"
  value       = local.secondary_subnets_by_az
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster. Referred to as 'Cluster security group' in the EKS console"
  value       = module.eks.cluster_primary_security_group_id
}
