# Security Policy

## Supported versions

Only the **latest published release** of pglayers receives security
fixes. We do not backport patches to older tags.

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.**

Please report them through [GitHub Security Advisories][advisory] on
this repository. This keeps the report private until a fix is available.

1. Go to the **Security** tab of this repository.
2. Click **Report a vulnerability**.
3. Describe the issue, including steps to reproduce if possible.

We will acknowledge receipt within 72 hours and aim to provide a fix
or mitigation within 14 days, depending on severity.

[advisory]: https://github.com/pglayers/pglayers/security/advisories/new

## Scope

This policy covers:

- The pglayers build system (Makefile, Dockerfiles, CI workflows)
- Extension packaging (incorrect library bundling, missing dependency
  isolation, file collisions that could cause security-relevant
  behavior changes)
- Published container images on GHCR (`ghcr.io/pglayers/*`)

This policy does **not** cover vulnerabilities in upstream projects
(PostgreSQL, individual extensions, base OS packages). Please report
those to the respective upstream maintainers. If an upstream CVE
affects a bundled extension or library, we will update the affected
layer promptly once a fix is available upstream.

## Disclosure

We follow coordinated disclosure. Once a fix is released, we will
publish a GitHub Security Advisory with details and credit the
reporter (unless they prefer to remain anonymous).
