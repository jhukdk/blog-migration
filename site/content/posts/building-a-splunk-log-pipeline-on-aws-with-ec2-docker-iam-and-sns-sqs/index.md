---
title: "Integrating Splunk Enterprise on AWS: EC2, Docker, IAM, and SNS/SQS Log Ingestion Pipeline"
date: 2026-06-30T00:30:00+00:00
slug: "integrating-splunk-enterprise-on-aws"
tags: ["aws", "splunk", "terraform", "ec2", "docker", "iam", "sns", "sqs", "ebs", "security", "observability", "logging"]
categories: ["DevOps", "Security"]
showTableOfContents: true
draft: false
---

My blog runs as a static S3 origin behind CloudFront, deployed by Terraform and GitHub Actions. The edge was producing access logs, but they were sitting inert in object storage. I could not yet answer questions and produce intelligence like: Who is requesting what? Why are certain clients requesting paths or filenames that result in 403 or 404? How often does CloudFront serve from cache versus reaching back to S3? 

This post documents the system I built to fix that: a **Splunk Enterprise** instance, running in Docker on a dedicated EC2 host, that ingests the blog's CloudFront access logs through a notification-driven pull pipeline. It is provisioned entirely as Terraform infrastructure-as-code in a separate repository from the blog. It holds **no static AWS credentials anywhere**. I will walk through each architectural decision and the reasoning behind it, because the *why* is the part worth reviewing.

## The Architecture at a Glance

The design follows Splunk's recommended pattern for ingesting from S3 at scale: rather than pushing events into Splunk, a notification path tells Splunk that a new log file exists, and Splunk *pulls* the object on its own schedule.

{{< mermaid >}}
flowchart LR
    CF["CloudFront access logs"] --> S3[("S3 logs bucket")]
    S3 -- ObjectCreated --> SNS["SNS topic"]
    SNS --> SQS["SQS queue"]
    SQS -. failures .-> DLQ[("Dead-letter queue")]
    SQS -- pointer --> Splunk["Splunk Enterprise<br/>(Docker on EC2)"]
    S3 -- pull object --> Splunk
    Splunk --> IDX[("index=cloudfront<br/>on EBS")]
{{< /mermaid >}}

The contract between the pieces is deliberate: **the SQS message is only a pointer** that says "a new log object landed." Splunk's *Splunk Add-on for AWS*, using its SQS-Based S3 input, reads that pointer, fetches the actual gzip log object from S3, parses it, and writes the events to a dedicated index. Decoupling notification from data transfer is what makes the design scale and recover cleanly: if Splunk is down for an hour, the pointers wait safely in the queue.

## The EC2 Instance: A Deliberately Small, Disposable Host

Splunk Enterprise runs on a single EC2 instance on Amazon Linux 2023. Two decisions here are worth justifying.

**Instance sizing.** Splunk's reference specification is generous, but my ingest volume — the access logs of one low-traffic blog — is tiny. I started with the smallest instance that could comfortably run the container, treating size as a one-line variable I can raise later if search feels sluggish. A real-world constraint shaped the final choice: the AWS account is on the new **Free plan**, which refuses to launch any instance type that is not free-tier-eligible. That ruled out my first pick and pushed me to a free-tier-eligible instance that, as it happened, carries *more* memory than my original plan. Documenting that pivot matters more than hiding it: infrastructure work is full of constraints discovered at apply time, and the useful skill is adapting cleanly rather than pretending the first plan was perfect.

**The host is disposable by design.** I configured the instance so it can be destroyed and rebuilt at will. All bootstrapping happens in EC2 user-data — install Docker, mount storage, fetch secrets, run the container — and Terraform is set to *replace* the instance whenever that script changes. This is only safe because the actual state lives elsewhere, on a separate disk, which is the next decision.

I also required **IMDSv2** on the instance. The instance metadata service is where the host's temporary credentials are delivered; forcing a session token closes the classic server-side request forgery path that has been used to steal those credentials through a vulnerable app.

## EBS: Why Splunk's Data Lives on a Separate Disk

If the instance is disposable, the indexed logs and Splunk's configuration cannot live on it. They live on a dedicated, encrypted **gp3 EBS volume** — a virtual disk attached to the instance, like an external SSD you can unplug from one machine and plug into another.

The Splunk container's two important directories are bind-mounted onto that volume:

- `/opt/splunk/var` — the indexed event data
- `/opt/splunk/etc` — all configuration: indexes, installed add-ons, and the ingestion input itself

Because both live on EBS, the entire instance can be terminated and replaced and the data survives: the volume detaches from the dead instance and reattaches to the new one, and the bootstrap script mounts it (skipping the format step when it sees an existing filesystem). This is the whole reason to use EBS rather than the instance's ephemeral disk — and I got to verify it the unplanned way: a later Terraform change altered the bootstrap script, which triggered a full instance replacement mid-build. The old host was terminated, a new one came up, the volume reattached, and every index definition and indexed event was still there. The failure mode I was designing against became the test that proved the design.

One concrete gotcha I had to handle: the official Splunk image runs as a specific non-root user (`uid 41812`), so the mounted directories have to be owned by that user or first-boot provisioning fails on permissions. The bootstrap script `chown`s them before starting the container.

## Docker: Running Splunk as a Container

Rather than installing Splunk directly onto the OS, I run the official `splunk/splunk` image, pinned to a specific patch version for reproducible builds. Containerizing buys clean upgrades (change the tag, replace the container) and keeps the host itself almost stateless.

The bootstrap runs roughly this:

```bash
docker run -d --name splunk --restart unless-stopped \
  -p 8000:8000 \
  -e SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com \
  -e SPLUNK_START_ARGS=--accept-license \
  -e SPLUNK_PASSWORD="$(fetched from SSM at boot)" \
  -v /opt/splunk-data/var:/opt/splunk/var \
  -v /opt/splunk-data/etc:/opt/splunk/etc \
  splunk/splunk:10.2.4
```

Two details earned their keep. First, Splunk 10.x added a *second* license-acceptance gate (`SPLUNK_GENERAL_TERMS`) on top of the older `SPLUNK_START_ARGS` flag; without it the container crash-loops on every boot with a "License not accepted" error. I discovered this the way you usually do — by watching the first deploy fail — and pinning a current major version is exactly the kind of change that surfaces such requirements. Second, the admin password is **never** written into the image, the Terraform code, or the state file.

## Secrets: SSM Parameter Store, Fetched at Boot

The Splunk admin password is stored as an **SSM Parameter Store SecureString**, created out-of-band so its value never enters the codebase or Terraform state. At boot, the instance fetches it using its own IAM role and feeds it to the container as an environment variable. Parameter Store (rather than Secrets Manager) is the right tool here because it is free and I do not need rotation features yet — choosing the cheaper service when its capabilities are sufficient is part of cost-aware design.

## IAM: One Role, a Trust Policy, and Least-Privilege Permissions

No static access keys exist anywhere in this system. The instance authenticates to AWS entirely through an **EC2 instance role** that delivers temporary, auto-rotated credentials through the metadata service. An IAM role answers two separate questions, and keeping them distinct is central to the model.

### Trust Policy — Who May Assume the Role?

The trust policy controls admission. For an instance role, only the EC2 service may wear it:

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "ec2.amazonaws.com" },
  "Action": "sts:AssumeRole"
}
```

Without this "who is allowed to assume me" statement, the role is unusable. It is the gate; the permissions below are what is on the other side of it.

### Permissions Policy — What May the Role Do?

The permissions are scoped to exact resources and actions — never `s3:*` or `sqs:*` on `*`. The role may:

- **Use SSM Session Manager** (`AmazonSSMManagedInstanceCore`) for shell access.
- **Read one parameter** — the admin password — plus the KMS decrypt needed to unwrap a SecureString, with KMS scoped so it only works *through* SSM.
- **Consume one queue** — `ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility`, `GetQueueAttributes`, `GetQueueUrl` on the specific queue ARN. No `SendMessage`, no access to the dead-letter queue.
- **Read one bucket** — `GetObject` on the logs bucket and `ListBucket` on it. Read-only; nothing touches the blog's content bucket.

```json
{
  "Effect": "Allow",
  "Action": [
    "sqs:ReceiveMessage", "sqs:DeleteMessage",
    "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"
  ],
  "Resource": "arn:aws:sqs:us-east-1:<account>:jhuk-tech-cf-logs"
}
```

> The blast radius is the point. Even if this role were assumed by something it should not be, it could drain one queue and read one bucket of access logs — nothing more.

There was one honest compromise. The Splunk add-on calls `sqs:ListQueues` when you create the input, and that API has *no* resource-level scoping in IAM — it is account-wide or nothing. I granted it deliberately and documented why: it exposes queue *names*, not message contents. Real least-privilege work includes naming the exceptions you accept and the reason they are acceptable, not pretending none exist.

### Shell Access Without an Open Port

Because the role carries SSM permissions, I get an interactive shell on the instance through **SSM Session Manager** — and port 22 stays closed to the internet entirely. There is no SSH key to manage or leak, and access is gated by IAM rather than by a key pair. This is strictly better than opening SSH to the world, and better even than locking SSH to my IP.

## Networking: A Custom VPC, Not the Default

I built a custom **VPC** (Virtual Private Cloud — my own isolated slice of the AWS network) rather than using the account's default, both for isolation and to make every networking component explicit. The pieces:

- **Subnet** — a range of addresses within the VPC where the instance lives.
- **Internet Gateway (IGW)** — the on-ramp between the VPC and the public internet. It does nothing until a route points at it.
- **Route Table** — the signposts. A default route (`0.0.0.0/0 → IGW`) is what actually makes the subnet "public"; associating it with the subnet is the step that turns it on.
- **Security Group (SG)** — a stateful firewall around the instance. It is default-deny inbound. I open exactly one port:

```hcl
# Inbound: Splunk Web (8000) from my IP only. No SSH (22) at all.
ingress 8000/tcp  from admin_cidrs
egress  all       to 0.0.0.0/0
```

Splunk's web UI (port 8000) is reachable only from my own IP, parameterized so it never lands hardcoded in the code. Egress is left open so the host can reach S3, SQS, SSM, and Docker Hub. For a single trusted host, locking inbound while allowing outbound is the right asymmetry.

## SNS and SQS: The Notification-Driven Pull Pattern

This is the heart of the ingestion design, and the pattern generalizes well beyond Splunk.

When CloudFront writes a new gzip log object, S3 emits an **ObjectCreated** event. That event publishes to an **SNS topic** (a publish/subscribe fan-out), which delivers to an **SQS queue** (a durable pull-based queue that Splunk polls).

A reasonable question is why SNS sits in the middle rather than wiring S3 straight to SQS. The answer is **fan-out**: a single S3 event can later feed additional consumers — a WAF pipeline, a CloudTrail pipeline, an alerting Lambda — without ever touching the S3 configuration again. SNS is the seam that keeps the design extensible. The cost is one extra hop and two resource policies.

Three engineering details make this production-shaped rather than a toy:

1. **A dead-letter queue (DLQ).** If Splunk fails to process a message a set number of times, SQS moves it to a sidecar queue instead of redelivering it forever or losing it. Failures become inspectable rather than silent.
2. **Tightly-scoped resource policies.** Each service must be *explicitly* allowed to call the next, and I constrain each grant with a `SourceArn` condition: S3 may publish to the topic only from my specific bucket; SNS may deliver to the queue only from my specific topic. This is the step people forget, and it fails quietly when skipped.
3. **A visibility timeout long enough to fetch and index** before a message could reappear, so the same object is not processed twice.

The result is a pipeline that is asynchronous, resilient to consumer downtime, and ready to carry more log sources than the one it serves today.

## A Cross-Repository Boundary Done Carefully

The Splunk stack lives in its own repository, separate from the blog. That separation forced a clean question: the blog's CloudFront distribution must be told to write logs to a bucket the *other* repo owns. I did not reach across and manage the distribution from the Splunk repo. Instead, the logs bucket uses a **deterministic name** that both repositories compute identically, and enabling logging was a single, reviewed change to the blog's distribution in its own repository. Each repo owns its resources; the only coupling is a name both sides agree on in advance.

One subtlety bit here and is worth flagging because it fails *silently*: CloudFront's legacy standard logging delivers files as a separate AWS account and grants ownership through a **bucket ACL**. Modern S3 buckets disable ACLs by default, which makes delivery quietly fail — no error, no logs. The fix is to re-enable ACLs on that bucket and grant the log-delivery account access. Knowing where a system fails without complaint is often more valuable than knowing the happy path.

## What Now Lands in Splunk — and What I Can Ask

With the pipeline live, every request to the blog produces a CloudFront access-log record that flows into Splunk within minutes, parsed into fields under a dedicated `index=cloudfront` with the `aws:cloudfront:accesslogs` sourcetype. The add-on extracts the full set of CloudFront W3C fields, including:

- `c_ip` — the client IP that made the request
- `cs_method`, `cs_uri_stem`, `cs_uri_query` — the HTTP method and requested path
- `sc_status` — the response status code (200, 404, 403, …)
- `x_edge_result_type` — cache outcome (`Hit`, `Miss`, `RefreshHit`, `Error`)
- `x_edge_location` — which CloudFront edge served the request
- `sc_bytes`, `time_taken` — response size and latency
- `cs_user_agent`, `cs_referer` — client and referrer

That turns inert log files into questions I can answer in seconds:

```spl
# Status-code breakdown
index=cloudfront | stats count by sc_status | sort -count

# Cache hit ratio — am I actually offloading work to the edge?
index=cloudfront
| eval cache=if(x_edge_result_type IN ("Hit","RefreshHit"),"hit","miss_or_other")
| stats count by cache

# Top requested paths
index=cloudfront | top limit=20 cs_uri_stem
```

I can see which posts draw traffic, whether the edge cache is doing its job, where 404s come from, and which client IPs and user agents are hitting the site — including the steady background of bots and scanners that every public site attracts. That background showed up in the very first batch of logs: a large share of the denied (`403`) requests were automated probes for paths like `/1ark.php` and `/wp-json/wp/v2/users` — scanners fishing for a vulnerable PHP or WordPress install on a site that runs neither. Within minutes of turning the pipeline on, inert log files had become a live feed of who was knocking and what they were looking for.

## What Comes Next

The same SNS/SQS pull pattern is built to extend. The two planned additions reuse it directly:

- **AWS WAF logs**, shipped through Kinesis Firehose into Splunk's **HTTP Event Collector** (a token-authenticated push endpoint) — letting me correlate blocked requests at the edge with the access logs already flowing.
- **CloudTrail**, the audit log of AWS API calls against the account, through the same S3 → SNS → SQS path — so changes to the infrastructure itself become searchable alongside the traffic it serves.

## Why This Design Holds Up

- **No standing credentials.** The host authenticates through an instance role with auto-rotating temporary credentials; the only secret, the admin password, lives in SSM and never enters code or state.
- **Least privilege, with documented exceptions.** Every grant is scoped to exact ARNs, and the one unavoidable account-wide permission is named and justified.
- **No open management ports.** Shell access is via SSM Session Manager; only the web UI is exposed, and only to my own IP.
- **State survives the host.** Indexed data and configuration live on EBS and outlive any instance replacement.
- **Resilient, extensible ingestion.** A pointer-based SNS/SQS pipeline with a dead-letter queue decouples producers from the consumer and is ready to carry more log sources without redesign.
- **Infrastructure as reviewable code.** Every resource is Terraform, versioned, and merged through pull requests — the security-relevant changes (a new IAM permission, an opened port) are visible in a diff before they exist.

The blog was already live. Now it is *observable* — and the pipeline that made it so is built to grow.
