# Architecture decisions — Segment 1 (containerize & deploy a single service)

Status: draft, entries added as decisions come up during the build.

## Terraform file organization: split by concern, not a security boundary

Decision: organized Terraform into one file per logical concern
(`versions.tf`, `variables.tf`, `vpc.tf`, `eks.tf`, `ecr.tf`,
`load-balancer-controller.tf`, `outputs.tf`) instead of one combined
`main.tf`.

Rationale: Terraform loads every `.tf` file in a directory as a single
merged configuration — there is no file-level scoping, isolation, or
security boundary created by this split. `terraform init`/`plan`/`apply`
behave identically either way. The split exists purely for:
- Readability as the project grows across later segments
- Cleaner, more focused Git diffs and PR reviews
- Enabling path-scoped review rules (e.g. a GitHub `CODEOWNERS` entry that
  requires specific review whenever `eks.tf` or
  `load-balancer-controller.tf` changes, since those touch IAM/IRSA)

Explicitly NOT achieved by this split:
- No blast-radius isolation. All files still compile into one Terraform
  configuration writing to a single state file — anyone who can
  `terraform apply` this directory can modify any resource in it,
  regardless of which file declares it.
- No secrets-scanning or governance benefit beyond making it easier for a
  human reviewer to spot something like a `Resource: "*"` creeping back
  into a smaller, focused diff.

Open follow-up: if genuine blast-radius isolation is needed later (e.g. a
"networking" apply role that structurally cannot touch IAM resources),
that requires separate Terraform root modules with separate state files,
each applied by its own least-privileged role — a larger architectural
step, intentionally out of scope for this segment's size.

## Exposing the service: NLB via Service, not ALB via Ingress

Decision: expose the app with a Kubernetes `Service` (type=LoadBalancer),
provisioning an AWS Network Load Balancer (NLB) through the AWS Load
Balancer Controller — not a Kubernetes `Ingress` provisioning an
Application Load Balancer (ALB).

Rationale: this segment has exactly one service and no content-based
routing decisions to make. NLB (Layer 4, TCP passthrough) gets a working
public endpoint with the fewest moving parts — just a `Service`, no
separate `Ingress`/`IngressClass` resource. ALB's Layer 7 features (host
or path routing, WAF integration, ACM-managed TLS termination) would go
entirely unused here.

When to revisit: the moment there's more than one service sharing a
domain/path space, or a need for AWS WAF or centralized TLS termination —
that's the natural trigger to add an `Ingress` + ALB instead.

## Node compute: Spot instances, not On-Demand

Decision: the EKS managed node group uses `capacity_type = SPOT`.

Rationale: significantly cheaper for a personal learning/portfolio
project, where occasional node interruption is an acceptable trade-off.

Trade-off accepted: AWS can reclaim Spot nodes with a two-minute warning.
This project uses a single node group without instance-type or
multi-AZ diversification, so interruption risk is somewhat correlated —
fine here, but a real production setup would diversify instance types
and pair Spot with pod disruption budgets before relying on it further.

## SSO permission set: PowerUserAccess + custom IAM policy, not AdministratorAccess

Decision: the AWS IAM Identity Center permission set used to run Terraform
combines the AWS managed policy `PowerUserAccess` with a custom
supplemental inline policy (`iam-supplemental-policy.json`) covering the
IAM actions PowerUserAccess intentionally excludes: role/policy
creation, `iam:PassRole`, service-linked role creation, and OIDC
provider management.

Rationale: `AdministratorAccess` would have been simpler to set up, but
grants unrestricted access across every service including IAM and
Organizations management. `PowerUserAccess` deliberately excludes IAM
write actions by design, so a narrow supplemental policy was added to
unblock exactly what Terraform needs — nothing more.

Follow-up hardening already applied: the supplemental policy's
`Resource` fields are scoped to this project's naming prefix
(`segment1-app-*`) rather than `"*"`, and `iam:PassRole` /
`iam:CreateServiceLinkedRole` each carry a `Condition` restricting which
AWS service they can be used with — see `iam-supplemental-policy.json`
for the current version and reasoning.

## Compute platform: EC2-backed node group, not Fargate

Decision: EKS compute uses an EC2-backed managed node group, not AWS
Fargate.

Rationale: Fargate is a legitimate, fully serverless alternative for this
segment's single-service workload considered in isolation. However,
Segment 4 of this same portfolio project is built around Karpenter,
which is fundamentally a node-level (EC2) autoscaler with no equivalent
on Fargate. Keeping Segment 1 on EC2-backed nodes means the same
cluster/infra carries forward into Segment 4 without a rebuild.

Trade-off accepted: Fargate would have been simpler to configure (no
node group, no Spot interruption risk) and possibly cheaper for this
specific low-traffic placeholder workload. Chosen in favor of roadmap
consistency over this segment's standalone simplicity — a deliberate
trade-off, not an oversight.

## ECR repository: force_delete enabled

Decision: `aws_ecr_repository.app` sets `force_delete = true`.

Rationale: this project gets rebuilt repeatedly while learning
(destroy/apply cycles), and AWS refuses to delete a non-empty ECR
repository by default. Without this flag, every `terraform destroy`
would fail on the ECR resource unless images were manually deleted
first.

Trade-off accepted: this makes it possible to destroy container images
with no confirmation step. A real production repository would very
likely leave this `false`, requiring deliberate manual image cleanup
before the repo itself could ever be torn down — intentionally
different behavior for a learning sandbox vs. production.

## Debugging technique: AWS IAM Access Troubleshooter

Every `AccessDenied` error from the AWS CLI/SDK includes a link like:
```
https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/authorization-details/<id>
```
Opening it shows the exact `Resource` ARN and `Result` (implicit vs.
explicit deny) AWS actually evaluated for that specific call — this is
what resolved several IAM issues during this build faster than guessing
at ARN patterns from documentation alone (e.g. discovering the SSO role's
path included a region segment, and that `AWSServiceRoleForAmazonEKSNodegroup`
is checked via `iam:GetRole` with no path prefix at all).

Example link encountered debugging the `iam:GetRole` denial on the EKS
node group's service-linked role check:
https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/authorization-details/cyq72wz0ipmttuknznetxjgkd

Note: this specific link is tied to that particular denied request and
may not remain accessible indefinitely — the technique (checking the
link every time a fresh `AccessDenied` appears) is the reusable lesson,
not this exact URL.

## Documentation policy: what gets screenshotted vs. described in prose

Decision: infrastructure and outcome screenshots (Terraform apply/destroy
output, EKS/ECR/VPC/NLB console views, `kubectl`/`helm`/`curl` output)
are included in the repo's documentation as-is. IAM Identity Center setup
screens, the AWS access portal, and Access Troubleshooter pages are
excluded from screenshots entirely, or heavily redacted if included —
described in prose in this file instead.

Rationale: the infra/outcome screenshots show status and results, and
carry little sensitive detail beyond the AWS account ID (which AWS treats
as an identifier, not a secret). The IAM/SSO-related screens are a
different category — collectively they exposed the AWS Organization ID
and OU path, a real source IP address, and (in one case) literal live
temporary access keys/session tokens on the "Get credentials" page. None
of that adds value for a reader over the prose explanation already in
this file, and screenshotting a live credentials page isn't a habit worth
normalizing even when the specific values shown have already expired.
