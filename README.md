# AWS DevOps Agent Lab

Infrastructure for testing an AWS DevOps Agent against Kubernetes incidents,
observability, and application troubleshooting on Amazon EKS.

## Phase 1 — Minimal EKS (this repo)

A small, low-cost EKS cluster `handsome-eks` in `ap-south-1`:

- VPC `K8s-VPC` (`10.20.0.0/16`) with 2 public + 2 private subnets.
- Private worker nodes, **no NAT Gateway** — AWS access via VPC endpoints.
- EKS with essential AWS-managed add-ons only (vpc-cni, coredns, kube-proxy,
  eks-pod-identity-agent).
- EKS Access Entries for IAM-based cluster access.

Terraform lives in [`terraform/`](terraform/). See its
[README](terraform/README.md) for usage, the Bastion→API path, the no-NAT
limitation, and a cost breakdown.

> Not installed in this phase (added later as needed): Prometheus, Grafana,
> Loki, Karpenter, AWS Load Balancer Controller.

## Quick start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform validate && terraform plan -out tfplan
# review, then when approved:
terraform apply tfplan
```

## Safety notes

- Uses the Bastion instance-profile credentials; no keys are hardcoded.
- State, `*.tfvars`, and secrets are gitignored.
- The existing Bastion EC2 instance and its Elastic IP are never modified.
