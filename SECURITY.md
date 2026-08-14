# Security Policy

## Supported versions

Before the first tagged release, only the current `main` branch is supported.
After releases begin, security fixes will target the latest release and
`main`; older releases may be unsupported unless stated otherwise.

## Reporting a vulnerability

Do not disclose vulnerability details in a public issue or discussion.

Use the repository's
[private vulnerability reporting form](https://github.com/LLMNetOps/clab-mt/security/advisories/new)
when it is available. If it is unavailable, use a contact method listed on the
[LLMNetOps organization profile](https://github.com/LLMNetOps), or open a public
issue containing no sensitive details and ask the maintainers to establish a
private reporting channel.

Please include:

- the affected file, component, and version or commit;
- reproduction steps or a minimal proof of concept;
- the expected and observed impact;
- any known mitigations; and
- whether the issue has been disclosed elsewhere.

The maintainers will confirm receipt, investigate, and coordinate remediation
and disclosure according to severity and available capacity.

## Lab credentials and deployment scope

The lab intentionally keeps the default RouterOS `admin` / `admin` credential,
and the checked-in eBGP TCP MD5 strings are lab-only values, not production
secrets. Their presence alone is not a vulnerability. Do not expose a deployed
lab to untrusted networks, and never reuse these values outside this testbed.
