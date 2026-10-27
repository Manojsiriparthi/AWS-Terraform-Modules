# ==============================================================================
# MODULE: IAM — Outputs
# ==============================================================================

output "ec2_instance_profile_name" {
  description = "Instance profile name to attach to EC2 instances"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2.arn
}

output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_nodes_role_arn" {
  description = "ARN of the EKS nodes IAM role"
  value       = aws_iam_role.eks_nodes.arn
}
