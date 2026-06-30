---
title: "Migrating my blog from WordPress to AWS using Github and Terraform"
date: 2026-06-15T12:00:00+00:00
slug: "migrating-my-blog-from-wordpress-to-aws-using-github-and-terraform"
categories: ["Writeup", "DevOps"]
draft: false
---
For years, I used a managed WordPress instance behind a cPanel host to write this blog. Initially it was a great way to learn. I was able to abstract away hosting-as-a-service. But Wordpress exposes an administrative login page and my comments section was open to the public internet which resulted in many cybersecurity issues such as brute-force authentication and botnets posting XSS payloads and gambling links. As my interests grew farther into cloud and DevOps, I wanted my own site to reflect the way I now think about infrastructure—**version-controlled, reproducible, and declarative in nature.**

I migrated the entire installation to a [Hugo](https://gohugo.io) static site hosted on **AWS S3 + CloudFront**, provisioned entirely with **Terraform** and deployed by **GitHub Actions**. Here is a breakdown of the architecture and the decisions behind each piece.

## Why Leave WordPress?

A static site removes an enormous amount of attack surface. There is no database, no server-side code execution, and no admin panel exposed to the world—just HTML, CSS, and images sitting in object storage. It is also dramatically cheaper to run and effectively immune to traffic spikes, because a CDN is serving flat files rather than rendering pages on every request.

The trade-off is that you give up the WordPress dashboard. For me that was a feature, not a loss. Writing in Markdown inside my own editor, committing to Git, and letting a pipeline publish the result is a workflow I already trust from software projects.

## The New Stack

The migrated site is built from four moving parts that each do one job well:

- **Hugo** with the [Congo](https://github.com/jpanther/congo) theme renders Markdown into a fast, themed static site. Congo is pulled in as a Hugo Module rather than a submodule, so the theme version is pinned in `go.mod` and updates are explicit.
- **Amazon S3** holds the built site in a **private** bucket. Nothing is served publicly from S3.
- **Amazon CloudFront** sits in front of the bucket and is the only thing allowed to read it, using an **Origin Access Control (OAC)** signature.
- **Terraform** describes every one of those resources as code, so the entire stack can be reviewed in a pull request and rebuilt from scratch.

## Infrastructure as Code

I made a rule for myself early on: nothing gets clicked into existence in the AWS console. Every bucket, distribution, certificate, and IAM role lives in Terraform under a `/infra` directory, with one concern per file (`s3.tf`, `cloudfront.tf`, `acm.tf`, `iam_oidc.tf`, and so on). Remote state lives in a versioned S3 bucket with native locking, so I can plan and apply safely from anywhere.

> **Note on Security:** Following the principle of least privilege, the content bucket stays completely private and is reachable only through CloudFront's OAC. The deploy pipeline assumes a dedicated IAM role scoped to exactly two things: read/write on the one content bucket and `cloudfront:CreateInvalidation` on the one distribution. Nothing more. There are also **no long-lived AWS keys stored anywhere**—more on that below.

## Preserving the Past: Content and Permalinks

One important constraint of the project was **not breaking existing links.** Every post that had been indexed by search engines and shared over the years used WordPress's dated permalink structure, and I intended to preserve it exactly.

I exported the old site to a WordPress WXR file and Claude Code helped me write a small Python script to convert each post into a Hugo page bundle—an `index.md` with clean front matter, alongside its original images. The Hugo config then locks the permalink pattern to match WordPress precisely:

```toml
[permalinks]
  posts = "/:year/:month/:day/:slug/"
```

Preserving each post's original `slug` and publish date means a URL like `/2026/03/05/using-azure-infrastructure.../` resolves to the same content it always did. The SEO value built up over years stays intact.

Every migrated post kept its formatting and its embedded screenshots, co-located in the page bundle rather than scattered across a `wp-content/uploads` tree.

## "Pretty" URLs at the Edge

Static object storage has no concept of a directory index, but Hugo emits "pretty" URLs that look like directories (for example `/posts/`). To bridge that gap I attached a small **CloudFront viewer-request function** that appends `index.html` to directory-style paths so they resolve to the right object in S3.

That same function does double duty as the site's canonical-host guard: a request to `www.jhuk.tech` is **301-redirected** to the apex `jhuk.tech` before any rewriting happens. Only one function may bind per event type at the edge, so both concerns live together in a single, well-commented file.

## Continuous Deployment Without Stored Keys

The part I am most happy with is the deployment pipeline. A push to `main` that touches the site triggers a GitHub Actions workflow that builds Hugo (extended, with Go available to fetch the Congo module), syncs the output to S3, and invalidates the CloudFront cache.

Crucially, it does all of this **without a single stored AWS credential.** The workflow uses **GitHub OIDC**: GitHub mints a short-lived identity token, AWS trusts it through an OIDC provider, and the pipeline assumes the least-privilege deploy role for the duration of the run. The trust policy is even scoped down to deploys from the `main` branch of this one repository. There is no access key to leak and nothing to rotate.

## The Roadmap Ahead

The site is live, the content is preserved, and every deploy is a single `git push`. The remaining work is mostly about cutover and polish:

- Adding more original write-ups now that publishing uses a GitHub Actions CI/CD pipeline.
- Continuing to harden and tidy the Terraform as the project grows.

Migrating off WordPress turned a blog into an infrastructure project, and that was exactly the point. I will keep documenting the journey as I build out the rest of my cloud and DevOps toolkit.
