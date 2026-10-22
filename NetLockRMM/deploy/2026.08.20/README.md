# NetLock RMM deployment release 2026.08.20

Superseded: do not use this release for new deployments. Use `2026.10.22` and its matching private ZIP. The older installer payloads can contain an incorrect Onboarding location. Existing agents do not need reinstallation merely to correct placement.

This release replaces the 2026.08 wrappers that embedded NetLock's retired long-lived password URLs.

- NetLock 3.2 file downloads use short-lived tokens.
- Each signed wrapper accepts its exact matching ZIP through an adjacent file, `-PackagePath`, or a URL serving those same bytes. A freshly generated console ZIP may not match.
- ZIP and embedded EXE SHA-256 values remain pinned per deployment.
- Tenant ZIPs are private release assets in `MSSP_Powershell_Signed`; they are not public.
- The Ed-only 0state deployment is intentionally excluded.

Use the exact deployment ID and package pairing recorded in Docmost. Do not edit a PS1 after signing.
