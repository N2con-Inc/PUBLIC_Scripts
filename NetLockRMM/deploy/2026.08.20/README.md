# NetLock RMM deployment release 2026.08.20

This release replaces the 2026.08 wrappers that embedded NetLock's retired long-lived password URLs.

- NetLock 3.2 file downloads use short-lived tokens.
- Each signed wrapper accepts an adjacent ZIP, `-PackagePath`, or a fresh `-PackageUrl`.
- ZIP and embedded EXE SHA-256 values remain pinned per deployment.
- Tenant ZIPs are private release assets in `MSSP_Powershell_Signed`; they are not public.
- The Ed-only 0state deployment is intentionally excluded.

Use the exact deployment ID and package pairing recorded in Docmost. Do not edit a PS1 after signing.
