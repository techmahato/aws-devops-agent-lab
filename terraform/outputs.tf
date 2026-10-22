###############################################################################
# VPC / Networking
###############################################################################

output "vpc_id" {
  description = "ID of the EKS VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR of the EKS VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (worker nodes)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "nat_gateway_count" {
  description = "Number of NAT gateways created (expected 0 in the no-NAT design)."
  value       = length(module.vpc.natgw_ids)
}

output "vpc_endpoint_ids" {
  description = "Map of interface VPC endpoint IDs."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "s3_gateway_endpoint_id" {
  description = "S3 gateway endpoint ID."
  value       = aws_vpc_endpoint.s3.id
}

###############################################################################
# EKS
###############################################################################

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version."
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Cluster security group ID managed by EKS."
  value       = module.eks.cluster_security_group_id
}

output "node_group_names" {
  description = "Managed node group names."
  value       = keys(module.eks.eks_managed_node_groups)
}

output "admin_access_entry_principal" {
  description = "IAM principal granted cluster-admin via EKS access entry."
  value       = local.admin_role_arn
}

###############################################################################
# Convenience
###############################################################################

output "update_kubeconfig_command" {
  description = "Run this on the Bastion to configure kubectl."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
