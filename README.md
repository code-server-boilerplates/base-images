# Base Docker image for `ghcr.io/code-server-boilerplate/*` images

[![Stability: Experimental](https://masterminds.github.io/stability/experimental.svg)](https://masterminds.github.io/stability/experimental.html) [![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-orange?logo=gitpod)](https://gitpod.io/#github.com/code-server-boilerplates/base-images)

## Included in this image

All the basics from an bare Debian install via buildpack-deps and plain bash, plus:

* pyenv and Node Version Manager
* code-server itself!
* Tailscale, although workaround is implemented to allow using it as an userspace tunnel on most SaaS services and to avoid needing `CAP_NET_ADMIN` for on-perm deployments.

## Usage

We'll slowly roll out this to our images in the coming weeks.

```Dockerfile
FROM ghcr.io/code-server-boilerplate/base

# your stuff goes here
```

## Customization 101

Since the base image is Debian-based, and not Ubuntu-based, we use the latest stable codename instead of going through `unstable` or `testing`.

Depending on your use case and distribution of choice, you may need to update literally everything other than `.gitpod.yml` and scripts under `hack` directory.
