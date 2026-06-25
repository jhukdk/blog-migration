---
title: "Using OIDC and JWT to Assume an AWS IAM Role in GitHub Actions"
date: 2026-06-24T12:00:00+00:00
slug: "using-OIDC-and-JWT-to-assume-an-AWS-IAM-role-in-GitHub-Actions"
tags: ["aws", "github-actions", "oidc", "terraform", "security", "ci-cd"]
categories: ["DevOps", "Security"]
showTableOfContents: true
draft: false
---

I wired up a GitHub Actions pipeline that runs `terraform plan` upon PR prior to merge. However for Terraform to compare the reality state of my existing AWS infrastructure, the CI pipeline first needs to assume a properly scoped AWS IAM role. The mechanism for this is called OIDC federation. This post walks through the technical procedure of issuing an OIDC token from the .yml pipeline, how the AWS IAM console is involved, and finally how the CI pipeline uses those temporary AWS credentials to complete its Terraform job.   

## The Problem: Authenticating a GitHub Actions VM

My infrastructure — an AWS WAFv2 Web ACL and an IP set — lives as Terraform IaC code in a repository. A CI job runs `terraform plan` on every pull request so that the exact effect of a change on AWS will be visible before the WAF rule is merged.

A GitHub Actions job runs on a fresh virtual machine that GitHub provisions and discards. It clones the repository and knows nothing else. It has no AWS credentials, and AWS refuses requests it cannot identify, so the job cannot touch the account unless it is given some way to authenticate. The question is how to grant a disposable, externally-hosted machine permission to act against an AWS account without leaving long-existing credentials behind.

## The Old Approach: A Stored Access Key

The conventional answer was to create a permanent AWS access key (an access key ID and secret, effectively a username and password for code), store it in **GitHub → Settings → Secrets**, and let the job read it at runtime.

This works, but it carries two distinct weaknesses:

1. **It is a long-lived secret at rest.** The key is valid until a human revokes it. If it leaks through a log line, a screenshot, or a compromised build dependency, an attacker holds standing access to the account indefinitely.
2. **It is not bound to any context.** Whoever holds the string is treated as the owner. AWS has no information about which workload is using it or where the request originated.

OIDC federation removes both weaknesses at once.

## Federation Instead of a Stored Secret

**Federation** means AWS does not authenticate the user directly with a username/password or long-lived AWS access keys. Instead, AWS trusts an external identity provider (IdP) to authenticate the caller and provide a signed assertion about their identity. AWS then uses that assertion to grant temporary credentials.

Here the external identity provider is **GitHub**, which operates an **OIDC provider** (OpenID Connect provider) at `token.actions.githubusercontent.com`. Its role is to issue signed statements about workflows on its platform: which repository a job runs in, on which branch, triggered by which event. GitHub vouches for the job, and AWS (configured in advance to trust that provider) issues **temporary** credentials in response. Nothing permanent is stored on either side.

## The Token Exchange

The handshake proceeds in four steps:

1. **The job requests an OIDC token from GitHub.** GitHub mints a freshly signed **JWT** (JSON Web Token). In its **`sub`** (subject) claim, the token records the repository and context the job is running in, for example `repo:jhukdk/my-repo:ref:refs/heads/main`.
2. **The job presents the JWT to AWS** through the `sts:AssumeRoleWithWebIdentity` call.
3. **AWS validates the token against a trust policy** defined in advance. If the JWT is signed by the trusted GitHub provider and its `sub` claim matches the configured condition, AWS issues **temporary credentials that expire in roughly an hour**.
4. **Terraform uses those temporary credentials** to read AWS and run its `plan`. The credentials expire shortly afterward.

{{< mermaid >}}
sequenceDiagram
    participant Job as GitHub Actions Job
    participant GH as GitHub OIDC Provider
    participant AWS as AWS STS

    Job->>GH: Request OIDC token
    GH-->>Job: Signed JWT (sub = repo:jhukdk/my-repo)
    Job->>AWS: AssumeRoleWithWebIdentity(JWT)
    AWS-->>Job: Temporary credentials (~1 hour)
{{< /mermaid >}}

This resolves both weaknesses of the stored key. Nothing durable is held at rest: the JWT is generated per run and the AWS credentials expire within the hour. And the request is cryptographically scoped, because the `sub` claim proves which repository the token came from, allowing AWS to reject every other caller.

### Two Short-Lived Tokens, Not One

A point worth separating explicitly, because the two tokens are easily conflated:

- The **OIDC JWT** is the identity assertion. It carries the `sub` claim and is used only for the handshake. It is valid for minutes.
- The **AWS temporary credentials** are what AWS returns after accepting the JWT. They perform the actual work and last about an hour.

The flow is: the JWT proves identity, and is exchanged for AWS credentials that do the work.

## The AWS Side: One Role, Two Policies

On AWS the caller assumes an **IAM role** — a set of permissions an identity is allowed to temporarily assume. The role carries **two** policies that answer two separate questions, and keeping them distinct is central to understanding the model.

### 1. Trust Policy — Who May Assume the Role?

The trust policy governs admission to the role:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:jhukdk/my-repo:*"
    }
  }
}
```

The `Principal.Federated` line establishes trust in GitHub's OIDC provider. The `Condition` on **`sub`** is the operative constraint: the role may be assumed only when the token reports that it originated from this specific repository. GitHub issues valid tokens for millions of repositories, and this condition is what restricts assumption to one of them. Tightening the pattern further — `:ref:refs/heads/main`, or a named environment — scopes it to a specific branch.

> GitHub *claims* an identity in the JWT's `sub`. The AWS **trust policy** is what *enforces* that claim. The protection holds only because both sides do their part: an honest assertion and a strict condition.

### 2. Permissions Policy — What May the Role Do?

The trust policy controls admission; the permissions policy controls capability once inside. Applying least privilege, a read-only `plan` needs only the read-only WAF calls Terraform issues:

```json
{
  "Effect": "Allow",
  "Action": [
    "wafv2:GetIPSet",
    "wafv2:ListIPSets",
    "wafv2:ListTagsForResource"
  ],
  "Resource": "*"
}
```

Scoping the policy this tightly keeps the blast radius minimal: even if the role were assumed by an unintended caller, it could read a few WAF facts and nothing more — no create, update, or delete. That is precisely why this is the `plan` role and not an `apply` role. Trust determines who is admitted; permissions determine what they can do.

## The Workflow

The relevant portion of `.github/workflows/terraform.yml`:

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # REQUIRED: lets the job request an OIDC token from GitHub
      contents: read    # lets actions/checkout read the repo
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}  # the role defined above
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform plan
```

The critical line is `id-token: write`. That permission is what authorizes the job to request the JWT from GitHub in the first place. Without it the handshake fails before it begins, since no token is ever minted. The `configure-aws-credentials` action performs the token-for-credentials exchange and exports the temporary credentials as environment variables, so the subsequent `terraform` steps authenticate automatically.

## Why This Pattern Follows Security Best Practices

- **No standing secret to steal.** The largest credential-leak class — a long-lived key in a CI system — does not exist in this design.
- **Identity is provable and scoped.** AWS confirms the request came from a specific repository and rejects all others.
- **Least privilege bounds the damage** if anything does go wrong.
- **It is auditable.** Every assumption appears in CloudTrail as `AssumeRoleWithWebIdentity`, tagged with the originating GitHub context.
