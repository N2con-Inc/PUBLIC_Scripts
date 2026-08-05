# NetLock RMM deployment release 2026.08

This release contains 16 public N2con-signed PowerShell bootstrap scripts and their signing manifests. Each opaque deployment ID maps to one shared N2con or client tenant in the internal Docmost deployment directory.

- Authorization ends at `2028-08-05 00:00:00`.
- N2con must regenerate and publish the replacement release by `2028-07-15`.
- Every script must retain a `Valid` Authenticode signature from `CN=N2CON Inc.`.
- Each `.manifest.json` file records the signed SHA-256 hash, signature result, timestamp result, and Azure DevOps build ID.
- The Ed-only 0state deployment is intentionally excluded from this public release.

Do not guess which opaque ID belongs to a customer. N2con technicians must use the exact URL or one-line command recorded in the internal deployment directory.
