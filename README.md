# N2con Public Scripts

This repository publishes PowerShell scripts that N2con technicians and deployment tools can download without requiring access to an internal system.

## Available script collections

- [`NetLockRMM`](NetLockRMM/README.md) - signed NetLock RMM deployment scripts and terminal one-liners

Additional script collections may be added as N2con standardizes other repeatable deployment and administration tasks.

## Trust and safety

- Treat this repository as a public distribution point, not an authoring workspace.
- Publish only reviewed release artifacts. PowerShell deployment scripts must carry a valid N2con code signature.
- Do not publish general credentials, customer names, tenant names, internal URLs, or documentation that maps an opaque deployment ID to a customer. A time-bounded enrollment URL may appear only inside an approved signed bootstrap script when public delivery is the intended design.
- Keep customer mappings, package-generation instructions, and approval records in N2con's internal documentation and signing repository.
- Pin downloaded installers or archives by cryptographic hash when the deployment workflow supports it.

Before running a script, review it and verify its Authenticode signature. Report security concerns according to [SECURITY.md](SECURITY.md).
