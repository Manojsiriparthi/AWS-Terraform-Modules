# ==============================================================================
# MODULE: EKS — Outputs
# ==============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "API server endpoint URL"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64-encoded CA certificate for kubectl config"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true   # mark sensitive so it doesn't print in plain text
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.main.version
}

output "node_group_status" {
  description = "Status of the managed node group"
  value       = aws_eks_node_group.main.status
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL (needed for IRSA — IAM Roles for Service Accounts)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
