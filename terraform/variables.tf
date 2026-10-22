###############################################################################
# General
###############################################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "handsome-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes control plane version."
  type        = string
  default     = "1.31"
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

###############################################################################
# Networking
###############################################################################

variable "vpc_name" {
  description = "Name tag for the VPC."
  type        = string
  default     = "K8s-VPC"
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC. Must not overlap the Bastion VPC (172.31.0.0/16)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "List of two Availability Zones to spread subnets across."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]

  validation {
    condition     = length(var.azs) == 2
    error_message = "Provide exactly two Availability Zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the two public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Provide exactly two public subnet CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the two private subnets (one per AZ). Worker nodes live here."
  type        = list(string)
  default     = ["10.20.32.0/20", "10.20.48.0/20"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Provide exactly two private subnet CIDRs."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway. Default false to minimize cost; private egress is served by VPC endpoints."
  type        = bool
  default     = false
}

###############################################################################
# EKS API endpoint access
###############################################################################

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the EKS API endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private (in-VPC) access to the EKS API endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Open to the internet per lab requirement; tighten for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# Managed node group
###############################################################################

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "EBS volume size (GiB) per worker node."
  type        = number
  default     = 20
}

variable "node_capacity_type" {
  description = "Capacity type for the node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

###############################################################################
# Control-plane logging
###############################################################################

variable "cluster_enabled_log_types" {
  description = "EKS control plane log types to enable."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch Logs retention (days) for EKS control plane logs."
  type        = number
  default     = 14
}

###############################################################################
# Access entries
###############################################################################

variable "bastion_admin_role_arn" {
  description = "IAM role ARN (e.g. the Bastion instance role) to grant cluster-admin via EKS access entry. Leave empty to auto-detect the caller."
  type        = string
  default     = ""
}
