name                             = "ai-on-eks-fsxl"
enable_aws_efa_k8s_device_plugin = true
enable_aws_fsx_csi_driver        = true
enable_kube_prometheus_stack     = true
enable_soci_snapshotter          = true
enable_nvidia_gpu_operator       = true
ami_family                       = "al2023"
availability_zones_count         = 3
region                           = "us-east-2"
eks_cluster_version              = "1.34"

enable_cluster_addons = {
  coredns                         = true
  kube-proxy                      = true
  vpc-cni                         = true
  eks-pod-identity-agent          = true
  metrics-server                  = true
  eks-node-monitoring-agent       = false
  amazon-cloudwatch-observability = false
}
