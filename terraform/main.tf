###############################################################################
# Lookups
###############################################################################

data "aws_caller_identity" "current" {}

# If no explicit admin role ARN is provided, grant cluster-admin to the caller
# (the Bastion instance role). We normalize the assumed-role ARN to its base
# IAM role ARN, which is what EKS access entries expect.
locals {
  caller_arn = data.aws_caller_identity.current.arn

  # arn:aws:sts::<acct>:assumed-role/<RoleName>/<session>  ->  arn:aws:iam::<acct>:role/<RoleName>
  derived_role_name = can(regex("assumed-role/", local.caller_arn)) ? element(split("/", local.caller_arn), 1) : null

  derived_admin_role_arn = local.derived_role_name != null ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.derived_role_name}" : local.caller_arn

  admin_role_arn = var.bastion_admin_role_arn != "" ? var.bastion_admin_role_arn : local.derived_admin_role_arn

  tags = merge(var.tags, {})
}

###############################################################################
# VPC  (official terraform-aws-modules/vpc)
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.azs
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_dns_support   = true
  enable_dns_hostnames = true

  # No NAT by default -> private nodes have no default route to the internet.
  # Private egress to AWS APIs is provided by the VPC endpoints below.
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.enable_nat_gateway

  # Subnet tags required by EKS and the AWS Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = local.tags
}

###############################################################################
# Security group for interface VPC endpoints (least privilege: 443 from VPC)
###############################################################################

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.cluster_name}-vpce-"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-vpce-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# VPC Endpoints  (enable no-NAT connectivity for private worker nodes)
#   - S3 gateway   : ECR image layers (stored in S3), plus general S3 access
#   - ECR API/DKR  : pull images from ECR
#   - EC2          : CNI / instance metadata style API calls
#   - STS          : IRSA / token exchange
#   - CloudWatch   : node & container logging
#   - EKS          : cluster API calls from within the VPC
###############################################################################

data "aws_region" "current" {}

# Gateway endpoint (free) - attached to private route tables for S3.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(local.tags, { Name = "${var.cluster_name}-s3-gw" })
}

locals {
  interface_endpoints = {
    ecr_api = "com.amazonaws.${var.region}.ecr.api"
    ecr_dkr = "com.amazonaws.${var.region}.ecr.dkr"
    ec2     = "com.amazonaws.${var.region}.ec2"
    sts     = "com.amazonaws.${var.region}.sts"
    logs    = "com.amazonaws.${var.region}.logs"
    eks     = "com.amazonaws.${var.region}.eks"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = module.vpc.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${var.cluster_name}-${each.key}" })
}

###############################################################################
# EKS  (official terraform-aws-modules/eks)
###############################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # API endpoint: private always; public optional and CIDR-restricted.
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Control plane logging + retention.
  cluster_enabled_log_types              = var.cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days

  # Recommended IAM access mechanism: EKS Access Entries (API + aws-auth).
  authentication_mode = "API_AND_CONFIG_MAP"
  # Disabled to avoid a duplicate access-entry collision: the cluster creator
  # (Custom-temp-Role) is already granted cluster-admin explicitly via the
  # bastion_admin access entry below. EKS allows only one entry per principal.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    bastion_admin = {
      principal_arn = local.admin_role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Essential AWS-managed add-ons only.
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # One managed node group, in the private subnets.
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      disk_size = var.node_disk_size

      subnet_ids = module.vpc.private_subnets
    }
  }

  tags = local.tags
}
