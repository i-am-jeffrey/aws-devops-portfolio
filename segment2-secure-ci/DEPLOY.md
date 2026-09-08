# Deploy runbook — Segment 2

Canonical, working sequence as of the first successful end-to-end run.
Every step below already has its known gotcha fixed in the workflow
itself.

## Prerequisites (applied once, via Terraform — not run per-session)

- `ci-cd-iam.tf` applied: two IAM roles, split by function --
  `segment1-app-gha-build` (ECR push only, trusted for
  `ref:refs/heads/main`) and `segment1-app-gha-deploy`
  (`PowerUserAccess` + supplemental IAM + `AmazonEKSEditPolicy` scoped
  to the `default` namespace, trusted only for the `production` GitHub
  Environment claim).
- GitHub Environment named exactly `production` created (Settings ->
  Environments).
- `.checkov.yaml` present at the repo root (Checkov suppression config
  — see the file itself for every suppressed check and why).

To confirm these are actually live before relying on them:
```bash
aws iam get-role --role-name segment1-app-gha-build --profile segment1-app-tf \
  --query 'Role.AssumeRolePolicyDocument'
aws iam get-role --role-name segment1-app-gha-deploy --profile segment1-app-tf \
  --query 'Role.AssumeRolePolicyDocument'
aws eks list-access-entries --cluster-name segment1-app-cluster \
  --region ap-southeast-1 --profile segment1-app-tf
```

## 1. How the pipeline triggers

Every push to `main` runs `.github/workflows/secure-ci.yml` automatically
— no manual step to kick it off. Three jobs run in sequence, each gated
on the last one succeeding: `static-scans` -> `build-scan-sign-push` ->
`deploy`.

## 2. Stage 1 — static scans

Gitleaks, Semgrep, and Checkov run independently (one failing does not
skip the others). No AWS credentials involved — safe on any push or PR,
including from a fork.

To verify: Actions tab -> the run -> `Secrets, SAST, IaC scan` job, or
Security -> Code scanning for the actual findings history.

## 3. Stage 2 — build, scan, sign, push

Only runs on push to `main` (never on a PR). Builds the image, scans it
with Trivy before it ever reaches the registry, pushes to ECR under an
immutable tag (the commit SHA), then signs it keylessly with Cosign
using this workflow's own GitHub OIDC identity.

To verify the real artifacts exist, not just that the job went green:
```bash
aws ecr describe-images --repository-name segment1-app \
  --region ap-southeast-1 --profile segment1-app-tf
```
Expect two entries: the image itself, and a second entry tagged
`sha256-<digest>.sig` — Cosign's actual signature artifact.

## 4. Stage 3 — deploy

Assumes the deploy role, updates kubeconfig, verifies the Cosign
signature **by digest** against the exact GitHub OIDC identity that
signed it, then — only if that passes — runs
`helm upgrade --install --atomic --wait --timeout 5m --history-max 5`
against the `segment1-app` chart in the `default` namespace. Deploys by
**tag** (the commit SHA), not digest — safe specifically because
`ecr.tf` enforces `image_tag_mutability = IMMUTABLE`, so the tag can
never point anywhere else.

Deliberately does **not** run `terraform apply`. Infra changes stay on
the same manual, human-reviewed `plan`-then-`apply` workflow used for
Segment 1 — this job only ever touches the application layer.

To verify:
```bash
kubectl get pods --namespace default -l app=segment1-app -o wide
kubectl get svc segment1-app --namespace default -o wide
```
Then hit the real endpoint from the `EXTERNAL-IP` shown:
```bash
curl http://<external-ip>/
curl http://<external-ip>/healthz
```

## Known issues already fixed in this repo's files (context, not action items)

- **Every scan step needs `if: always()`, not just its upload step.**
  GitHub Actions skips every step after the first failure in a job by
  default — without this, Semgrep finding a real issue silently
  prevented Checkov from ever running at all.
- **Checkov's own log message can lie about its output filename.** A
  known Checkov quirk means the SARIF file it actually writes doesn't
  always match what it claims to have written. The workflow uses
  `find checkov-output -name "*.sarif"` to locate the real file instead
  of assuming a name.
- **A `nosemgrep` suppression comment must sit immediately adjacent to
  the flagged line** — on it, or the single line directly above, with
  nothing else in between. Multi-line explanatory comments between the
  directive and the code it's meant to suppress silently break it.
- **`cosign verify` needs its own ECR login step, separate from AWS IAM
  permissions.** The deploy role already has broad ECR access via
  `PowerUserAccess` — that's a different layer from registry-level
  Docker/OCI authentication, which `cosign` needs explicitly. A `401
  Unauthorized` here means no registry credentials were ever presented,
  not that the IAM role lacks permission (which would surface as AWS's
  own `403 AccessDenied` instead).
- **All third-party GitHub Actions across the whole workflow are pinned
  to real, confirmed commit SHAs** — never floating version tags, and
  never guessed. Each one was taken directly from an actual "Set up
  job" log for this repo.

## Screenshots to capture for GitHub documentation

**GitHub:**
- [Actions tab — full pipeline run, all three jobs green in sequence](./screenshots/gh-actions-full-run.png)
- [The `Verify the image signature before deploying anything` step, expanded — real `cosign verify` output](./screenshots/gh-cosign-verify.png)
- [Security -> Code scanning — Tools overview showing Gitleaks, Semgrep, Trivy, Checkov all active](./screenshots/gh-code-scanning-tools.png)
- [Security -> Code scanning — resolved findings history (`is:closed branch:main`)](./screenshots/gh-code-scanning-closed.png)

**Terminal:**
- [`kubectl get pods -w` — real pods reaching `1/1 Running`](./screenshots/terminal-kubectl-pods.png)
- [`curl` output — real JSON response from the deployed app](./screenshots/terminal-curl.png)

**AWS Console:**
- [ECR repository — pushed image + its `.sig` signature artifact](./screenshots/aws-ecr-repo.png)
- [EKS Console -> Workloads -> Deployments — `segment1-app` showing 2/2 ready](./screenshots/aws-eks-workloads.png)
