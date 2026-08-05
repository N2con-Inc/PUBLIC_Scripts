# Contributing

This repository is the public distribution point for approved N2con scripts. Development, signing requests, customer mappings, and approval records belong in N2con's private workflow.

Before publishing a PowerShell artifact:

1. Remove customer-identifying information and unrelated secrets. An approved, time-bounded enrollment URL may remain only when it is the script's intended public bootstrap mechanism.
2. Complete review and approval in the private signing workflow.
3. Verify that the final file has a valid N2con Authenticode signature.
4. Test the exact signed artifact using its documented deployment method.
5. Publish the signed file without changing it after signing.
6. Record the public URL, hash, approval, owner, and rotation date in internal documentation.

Do not edit a signed `.ps1` file in this repository. Any content change requires a new review, signature, validation, and release.
