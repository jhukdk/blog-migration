---
title: "No More Long-Lived Keys: How GitHub Actions Talks to AWS with OIDC"
date: 2026-06-24T12:00:00+00:00
slug: "no-more-long-lived-keys-github-actions-aws-oidc"
description: "How a GitHub Actions workflow authenticates to AWS with zero stored secrets — JWTs, the sub claim, federation, and the IAM trust policy that ties it all together."
summary: "Stop pasting AWS access keys into GitHub Secrets. Here's how OIDC lets a CI job prove who it is and borrow short-lived AWS credentials instead — explained from the ground up."
tags: ["aws", "github-actions", "oidc", "terraform", "security", "ci-cd"]
categories: ["DevOps", "Security"]
showTableOfContents: true
draft: false
---

I just wired up a GitHub Actions pipeline that runs `terraform plan` against my AWS
account on every pull request — with **no AWS access keys stored anywhere**. The first
time you see it work it feels like magic: a robot on a rented Linux box, owned by GitHub,
somehow gets permission to read my AWS resources, and nothing secret ever changed hands.

It isn't magic. It's **OIDC federation**, and once it clicks it's one of the cleaner ideas
in cloud security. This post is me explaining it the way I wish someone had explained it to
me — one layer at a time, no hand-waving.

## The problem: the blank-stranger machine

Here's the setup. My infrastructure (an AWS WAF Web ACL and an IP set) lives as Terraform
code in a repo. I want a CI job to run `terraform plan` on every PR so I can *see exactly
what a change will do to AWS before it's merged.*

But a GitHub Actions job runs on a **fresh virtual machine that GitHub spins up and throws
away**. It's a blank stranger. It clones my repo, and that's all it knows. It has no idea
who I am and — crucially — it has **no AWS credentials**. AWS refuses to talk to anyone it
can't identify, so the job is dead on arrival unless I hand it some way to authenticate.

How do you give a throwaway machine permission to touch your AWS account?

## The old, bad answer: a stored access key

The obvious move is to create a permanent AWS access key (an access key ID + secret — a
username/password pair for code), paste it into **GitHub → Settings → Secrets**, and let
the job read it.

It works. It's also a bad idea, for two *separate* reasons worth keeping apart:

1. **It's a long-lived secret sitting at rest.** That key works *forever*, until a human
   remembers to delete it. If it ever leaks — a log line, a screenshot, a compromised
   dependency in your build — an attacker has standing access to your account indefinitely.
2. **It isn't tied to anything.** Whoever holds the string *is* you, as far as AWS is
   concerned. There's no context about *who* or *what* is using it or *from where.*

The whole point of OIDC is to delete both problems at once.

## The fix: federation instead of a stored secret

**Federation** means: instead of AWS holding its own copy of your credentials, it *trusts
an outside identity provider to vouch for you.* You already use this every time you "Sign in
with Google" somewhere — that site doesn't store your password; it trusts Google's say-so.

Here, the outside identity provider is **GitHub**. GitHub runs an **OIDC provider** (OpenID
Connect provider) at `token.actions.githubusercontent.com`. Its job is to issue signed
statements about workflows running on its platform: *"this job really is running in repo X,
on branch Y, triggered by event Z."*

So the new plan is: GitHub vouches for the job, and AWS — having been told ahead of time to
trust GitHub's vouching — hands over **temporary** credentials. Nothing permanent is stored
anywhere.

## The handshake, step by step

Read this slowly; it's the heart of the whole thing.

1. **The job asks GitHub for a token.** When the workflow runs, it requests an OIDC token
   from GitHub's provider. GitHub mints a brand-new, cryptographically **signed JWT** (JSON
   Web Token) — think of it as a tamper-proof ID badge. Inside, in a field called **`sub`**
   (subject), it stamps *which repo and context the job is running in*, e.g.
   `repo:jhukdk/my-repo:ref:refs/heads/main`.
2. **The job hands the JWT to AWS** and says: *"Based on this, may I become a role?"* The
   specific AWS call is `sts:AssumeRoleWithWebIdentity`.
3. **AWS checks the badge against a trust policy** you set up in advance (next section). If
   the badge is genuinely signed by GitHub *and* its `sub` matches what you said you'd
   accept, AWS issues **temporary credentials that expire in about an hour.**
4. **Terraform uses those temporary credentials** to read AWS, run its `plan`, and finish.
   An hour later (usually much sooner) they're useless.

Here's the whole exchange in one picture:

{{< mermaid >}}
sequenceDiagram
    autonumber
    participant Job as GitHub Actions Job<br/>(blank Ubuntu VM)
    participant GH as GitHub OIDC Provider<br/>token.actions.githubusercontent.com
    participant STS as AWS STS
    participant Role as IAM Role<br/>(+ trust & permissions policies)
    participant TF as Terraform → AWS WAF

    Note over Job: permissions:<br/>id-token: write
    Job->>GH: Request OIDC token
    GH-->>Job: Signed JWT (badge)<br/>sub = repo:jhukdk/my-repo:*
    Job->>STS: AssumeRoleWithWebIdentity(JWT)
    STS->>Role: Check trust policy<br/>Is JWT signed by GitHub?<br/>Does sub match this repo?
    alt sub matches the trusted repo
        Role-->>STS: ✅ Allowed
        STS-->>Job: Temporary credentials (~1 hour)
        Job->>TF: terraform plan with temp creds
        TF-->>Job: Plan output (scoped by<br/>least-privilege permissions policy)
    else sub is any other repo
        Role-->>STS: ❌ Denied
        STS-->>Job: AccessDenied — no credentials
    end
{{< /mermaid >}}

Now re-read those two original problems:

- **No secret at rest.** Nothing permanent is stored. The JWT is created fresh each run and
  the AWS credentials self-destruct in ~an hour. There's nothing durable to leak.
- **It's cryptographically scoped.** The JWT *proves which repo it came from* in the `sub`
  field, so AWS can refuse anyone else.

### Two short-lived tokens, not one

This tripped me up, so I'll call it out: there are **two** different temporary things, and
fusing them is the classic confusion.

- The **OIDC JWT** is the *ID badge*. It carries identity (`sub`) and is used only for the
  *handshake*. Very short-lived — minutes.
- The **AWS temporary credentials** are what AWS hands *back* after accepting the badge.
  *These* are what actually do the work, and they last ~1 hour.

So: **JWT (proves who you are) → exchanged for → AWS creds (do the work).**

## The AWS side: one role, two policies

On AWS you create an **IAM role** — "a set of permissions some identity is allowed to
temporarily assume." This role has **two** policies attached, and they answer two genuinely
different questions. Keeping them straight is the single most useful thing in this whole
topic.

### 1. Trust policy — *who is allowed to become this role?*

This is the bouncer at the door.

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

The `Principal.Federated` line says *"I trust badges from GitHub's OIDC provider."* The
`Condition` on **`sub`** is the important part: *"…but only if the badge says it came from
**this exact repo**."*

This one line is what stops every other repo on all of GitHub from assuming your role.
GitHub mints valid badges for millions of repos every day — but AWS only opens the door for
badges stamped with *yours*. Tighten it further (`:ref:refs/heads/main`, or an environment)
and you can require a specific branch.

> **The crucial split:** GitHub *claims* an identity in the JWT's `sub`. The AWS **trust
> policy** is what *enforces* the claim. The protection exists only because both sides do
> their job — an honest claim **and** a strict check.

### 2. Permissions policy — *what can you do once you're in?*

The trust policy gets you through the door. The permissions policy decides what you can
touch inside. Here's **least privilege** in action — for a read-only `plan`, the role can
do *only* the read-only WAF calls Terraform needs:

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

Why this matters: even if someone *did* manage to assume this role, the **blast radius is
tiny** — they could read a couple of WAF facts and nothing else. No create, no update, no
delete. (That's exactly why this is the `plan` role, not an `apply` role.)

**Trust = who gets in. Permissions = what they can do.** Two policies, two questions.

## The workflow that ties it together

Here's the relevant slice of `.github/workflows/terraform.yml`:

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
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}  # the role we built above
          aws-region: us-east-1

      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform plan
```

The line that surprises people is `id-token: write`. That permission is what lets the job
*ask GitHub to mint the JWT in the first place.* Leave it out and the whole handshake fails
before it starts — no badge, no entry. The `configure-aws-credentials` action does the
badge-for-credentials exchange and quietly sets the temporary creds as environment
variables, so `terraform` "just works" from there.

## A bonus gotcha: `Plan: 1 to add` for a thing that already exists

The first time my CI `plan` ran, it announced it would **create** an IP set that *already
existed* in AWS. I'd built it weeks earlier.

The reason is a perfect illustration of the blank-stranger machine. Terraform knows what
exists by reading its **state file** (`terraform.tfstate`) — its memory of what it has
built. That file lives **on my laptop** and is (correctly) git-ignored, because state can
contain secrets. The CI runner clones the repo, finds **no state file**, and therefore has
*amnesia*: it compares "the code says one resource should exist" against "I know of zero
resources" and concludes it must create one.

The fix is a **remote state backend** (e.g. an S3 bucket) so my laptop and the CI runner
read the *same* memory. It's the cleanest possible argument for shared remote state: two
machines literally disagreed about reality because they each had their own.

## Why this is the right pattern

- **No standing secret to steal.** The biggest credential-leak class — a long-lived key in
  a CI system — simply doesn't exist here.
- **Identity is provable and scoped.** AWS knows the request came from a specific repo, and
  refuses everything else.
- **Least privilege limits the damage** if anything *does* go wrong.
- **It's auditable.** Every assumption shows up in CloudTrail as
  `AssumeRoleWithWebIdentity`, tagged with the GitHub context.

If you're still pasting AWS keys into CI secrets, this is the upgrade. Set up the OIDC
provider once, write a tightly-scoped role, add `id-token: write`, and delete the keys.

---

*Notes from my path toward perimeter security engineering — managing AWS WAF with Python,
Terraform, and GitHub Actions.*
