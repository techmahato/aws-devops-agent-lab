# handsome-eks — Terraform

Minimal, low-cost Amazon EKS lab in `ap-south-1`, provisioned from the Bastion.
Private worker nodes, **no NAT Gateway**, private egress via VPC endpoints.

## Layout

```
terraform/
├── versions.tf              # Terraform & provider version pins, backend note
├── providers.tf             # AWS provider (uses instance-profile creds)
├── variables.tf             # All configurable inputs
├── main.tf                  # VPC, endpoints, EKS, node group, add-ons, access
├── outputs.tf               # Useful outputs
├── terraform.tfvars.example # Copy to terraform.tfvars and edit
└── README.md
```

## What gets created

| Component | Detail |
|-----------|--------|
| VPC `K8s-VPC` | `10.20.0.0/16`, DNS support + hostnames |
| Public subnets | 2 AZs, IGW route, `kubernetes.io/role/elb=1` |
| Private subnets | 2 AZs, **no NAT / no default route**, `kubernetes.io/role/internal-elb=1` |
| VPC endpoints | S3 (gateway) + ECR API, ECR DKR, EC2, STS, Logs, EKS (interface, private DNS) |
| EKS `handsome-eks` | k8s 1.31, public+private endpoint, control-plane logging |
| Node group | 1 managed group, 2× `t3.small`, private subnets, AL2023 |
| Add-ons | vpc-cni, coredns, kube-proxy, eks-pod-identity-agent (AWS-managed) |
| Access | EKS Access Entries (`API_AND_CONFIG_MAP`); Bastion role = cluster-admin |

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit if desired

terraform init
terraform validate
terraform plan -out tfplan

# Review the plan, then (only when approved):
terraform apply tfplan

# Configure kubectl on the Bastion:
aws eks update-kubeconfig --region ap-south-1 --name handsome-eks
kubectl get nodes
```

## Bastion → private EKS API

The Bastion lives in the **default VPC** `172.31.0.0/16`, which is separate from
this EKS VPC `10.20.0.0/16`. With no VPC peering, the Bastion reaches the API via
the **public endpoint** (restricted by `cluster_endpoint_public_access_cidrs`,
currently `0.0.0.0/0` per the lab requirement — tighten to the Bastion EIP
`3.108.68.87/32` for production). The private endpoint is also enabled so in-VPC
workloads resolve the API privately.

If you prefer a private-only endpoint, add VPC peering between `172.31.0.0/16`
and `10.20.0.0/16` (plus route-table and DNS-resolution settings) and set
`cluster_endpoint_public_access = false`. That avoids public exposure without a
NAT Gateway.

## No-NAT limitation

Private nodes have **no route to the public internet**. They can reach AWS
services that have a VPC endpoint here (ECR, S3, EC2, STS, CloudWatch Logs, EKS,
plus EKS-managed control-plane traffic). They **cannot**:

- `docker pull` from Docker Hub / quay.io / ghcr.io or any non-ECR registry
- `curl`/download from arbitrary public URLs
- reach third-party APIs/SaaS endpoints

If a later component needs public egress (e.g. Helm charts pulling images from
public registries), the lowest-cost secure options are, in order:

1. Mirror the required images into **ECR** (works today, no new cost).
2. Add a **single NAT Gateway** (`enable_nat_gateway = true`) — ~\$32/mo + data
   processing; simplest but recurring cost.
3. Add specific extra **interface endpoints** if the dependency is an AWS service.

## Remote state (recommended before team use)

State is currently **local** on the Bastion (`terraform.tfstate`). We did not
assume a remote bucket exists. For durability and locking, create a dedicated
S3 bucket (versioned, encrypted, public access blocked) + DynamoDB lock table,
then uncomment the `backend "s3"` block in `versions.tf` and `terraform init
-migrate-state`. Do not commit state or `*.tfvars` to Git.

## Cost (approximate, ap-south-1, on-demand)

| Item | Est. monthly |
|------|--------------|
| EKS control plane | ~\$73 (\$0.10/hr) |
| 2× t3.small nodes | ~\$30 |
| 6× interface endpoints | ~\$45 (\$0.01/hr each × 2 AZ ENIs ≈ varies) |
| EBS (2× 20 GiB gp3) | ~\$3 |
| S3 gateway endpoint | free |
| NAT Gateway | \$0 (disabled) |
| **Total** | **~\$150/mo** while running |

Destroy with `terraform destroy` when idle to stop charges.
