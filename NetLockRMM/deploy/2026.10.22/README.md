# NetLock deployment release 2026.10.22

These are final N2CON-signed, timestamped PowerShell wrappers. They contain no enrollment URL or customer names.

Use the exact deployment ID and private ZIP pairing recorded in Docmost. Place that ZIP beside the script or pass `-PackagePath`. A newly generated console ZIP may fail the pinned ZIP/EXE hashes.

- Enrolls into the intended customer's **Onboarding** location.
- Starts an existing stopped communication service; skips reinstallation when the service is already running.
- `SHA256SUMS` and adjacent manifests record the signed bytes and Azure signing evidence.
- Authorization ends at the start of **2028-08-05**. Regenerate by **2028-07-15**.
- 0state is intentionally excluded.

Use the private per-client MSI for standard Intune, NinjaOne, or GPO deployments. Pilot before broad assignment. Do not edit scripts after signing or mix releases.
