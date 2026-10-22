provider "aws" {
  region = var.region

  # Credentials come from the Bastion's instance profile / AWS CLI chain.
  # Never hardcode access keys or secrets.

  default_tags {
    tags = {
      Project   = "aws-devops-agent-lab"
      ManagedBy = "terraform"
      Cluster   = var.cluster_name
    }
  }
}
