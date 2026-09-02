# Deploy runbook — Segment 1

Canonical, working sequence as of the first successful end-to-end deploy.
Every step below already has its known gotcha fixed in the commands
themselves.

## Prerequisites (one-time per session)
```bash
aws sso login --profile segment1-app-tf
export AWS_PROFILE=segment1-app-tf
```

## 1. Provision infrastructure
```bash
cd terraform/
terraform plan -out=tfplan
terraform plan   # read it before applying
terraform apply tfplan
```
Note the `ecr_repository_url` and `configure_kubectl` values from the
output — you'll need both next.

## 2. Connect kubectl
```bash
aws eks update-kubeconfig --region ap-southeast-1 --name segment1-app-cluster --profile segment1-app-tf
kubectl get nodes            # both should show Ready
kubectl get pods -n kube-system | grep aws-load-balancer-controller   # should show 1/1 Running
```

## 3. Build and push the image
```bash
cd ../app
docker build --platform linux/amd64 --provenance=false -t segment1-app:v1 .
```
Both flags matter:
- `--platform linux/amd64` — EKS nodes are `t3.medium` (x86_64). Building
  without this on an Apple Silicon Mac produces an ARM64 image that fails
  with `exec format error` at container start.
- `--provenance=false` — without this, recent Docker versions attach a
  build-attestation manifest that wraps the image in an OCI index some
  container runtimes don't pull cleanly.

```bash
aws ecr get-login-password --region ap-southeast-1 --profile segment1-app-tf \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com

docker tag segment1-app:v1 <ecr_repository_url>:v1
docker push <ecr_repository_url>:v1
```
The repo has `image_tag_mutability = IMMUTABLE` — every rebuild needs a
new tag (`v1`, `v2`, ...); re-pushing the same tag fails on purpose.

## 4. Deploy with Helm
```bash
cd ../helm/segment1-app
pwd   # confirm this prints .../helm/segment1-app, NOT the project root
helm install segment1-app . \
  --set image.repository=<ecr_repository_url> \
  --set image.tag=v1
```
Use `helm upgrade` instead of `install` if the release already exists
(e.g. after pushing a new image tag without tearing down the cluster).

## 5. Verify
```bash
kubectl rollout status deployment/segment1-app
kubectl get pods -o wide            # expect 1/1 Running, low/no restarts
kubectl get svc segment1-app -o wide   # grab the EXTERNAL-IP hostname

curl http://<external-ip>/
curl http://<external-ip>/healthz
```

## Tearing down
```bash
helm uninstall segment1-app     # remove the app release first
cd ../../terraform
terraform destroy
```
`force_delete = true` on the ECR repo *should* let destroy remove it even
with images inside. In practice this didn't reliably prevent
`RepositoryNotEmptyException` — if `terraform destroy` fails on the ECR
resource with that error, empty the repo directly first, then retry:
```bash
aws ecr batch-delete-image \
  --repository-name segment1-app \
  --region ap-southeast-1 \
  --profile segment1-app-tf \
  --image-ids "$(aws ecr list-images --repository-name segment1-app --region ap-southeast-1 --profile segment1-app-tf --query 'imageIds[*]' --output json)"

terraform destroy
```
The KMS key won't delete instantly either — AWS schedules it for deletion
(7-30 day window); this is expected, not an error.

**If `terraform destroy` fails with `DependencyViolation` on the VPC**
(e.g. `"the vpc '...' has dependencies and cannot be deleted"`), this
means `helm uninstall segment1-app` was skipped or didn't
finish before terraform destroy ran. The AWS Load Balancer Controller's NLB (and
its network interfaces) lives in the VPC's subnets but was created by
Kubernetes, not Terraform — so Terraform has no way to clean it up
itself, and it blocks VPC deletion until it's gone. Fix: `helm uninstall
segment1-app` first (if the cluster still exists), or check the EC2
console's Load Balancers / Network Interfaces for that VPC directly and
delete any leftovers by hand, then retry `terraform destroy`.

## Known issues already fixed in this repo's files (context, not action items)
- Dockerfile: user must be created *before* `COPY --chown=...`, or a
  non-root container user gets "Permission denied" on its own files.
- `.helmignore`: without it, Helm may try to package unrelated files
  (e.g. Terraform's `.terraform/modules/*/.git/` cache) if `helm` is ever
  run from the wrong directory.
- `versions.tf`: the `helm` provider needs explicit `kubernetes {}`
  connection details, or `helm_release` fails with "cluster unreachable".
- `iam-supplemental-policy.json`: several `iam:GetRole`/`PassRole`
  resource patterns had to be widened based on actual ARNs seen in
  `AccessDenied` errors — module-generated role names/paths don't always
  match assumptions made ahead of time.

## Screenshots to capture for GitHub documentation

**AWS Console:**
- [EKS cluster overview (Clusters → segment1-app-cluster) — shows Active status, version](./screenshots/aws-eks-cluster-overview.png)
- [Node group detail — shows `Capacity type: Spot`, nodes Ready](./screenshots/aws-eks-nodes.png)
- [VPC Resource Map — shows subnets/AZs/NAT gateway in one diagram](./screenshots/aws-vpc-resource-map.png)
- [ECR repository — shows pushed image + vulnerability scan results](./screenshots/aws-ecr-repo.png)
- [EC2 → Load Balancers — shows the auto-provisioned NLB](./screenshots/aws-ec2-nlb.png)

**Terminal / VS Code:**
- [`terraform apply` final output (Apply complete + Outputs block)](./screenshots/aws-terraform-apply.png)
- [`kubectl get nodes` showing Ready](./screenshots/aws-kubectl-get-nodes.png)
- [`kubectl get pods -o wide` showing 1/1 Running](./screenshots/aws-kubectl-get-pods.png)
- [`kubectl get svc segment1-app -o wide` showing the NLB hostname](./screenshots/aws-kubectl-get-svc-sgement1-app.png)
- [`curl` output returning the app's JSON — the definitive proof-of-life shot](./screenshots/aws-curl.png)
- [`helm list` showing STATUS deployed](./screenshots/aws-helm-list.png)
