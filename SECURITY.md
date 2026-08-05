# Security policy

## Supported version

Security fixes are applied to the latest version on the `main` branch. Older commits are not considered supported after a fix is available unless explicitly stated otherwise.

## Reporting a vulnerability

Use GitHub private vulnerability reporting from the repository's **Security** tab. Do not publish working exploits, credentials, private network details, or unredacted connection output in a public issue.

Include the affected commit or version, reproduction steps, expected and actual behavior, impact, and any suggested mitigation. If private reporting is unavailable, open a public issue containing no sensitive details and request a private contact channel.

## Intended security boundary

`netpulse` is a local, read-only observer. It reads the Windows TCP connection table, queries local process metadata, and checks Authenticode signatures. It does not capture packets, inspect traffic contents, scan remote systems, make external requests, or modify processes, firewall rules, the registry, or system configuration.

The reported evidence has limits:

- a valid Authenticode signature does not prove an executable is safe
- an unsigned executable is not proof of malicious behavior
- address scope is a coarse classification and does not establish identity, reachability, or trust
- process names, paths, and signatures can become unavailable because processes may exit or access may be restricted
- five-second sampling can miss short-lived connections

`netpulse` is not an intrusion-detection system and should not be used as the sole basis for a security decision.

## Privacy

Terminal output can contain process names, process identifiers, local addresses, remote addresses, and ports. Treat captured output as potentially sensitive and redact it before posting screenshots, issues, or support requests.

`netpulse` keeps watch state only in memory and does not create reports, logs, telemetry, or history files.

## Execution policy

Review `netpulse.ps1` before running it. If Windows blocks local scripts, the documented `-ExecutionPolicy Bypass` command applies only to the new PowerShell process and does not change the persistent user or machine policy.
