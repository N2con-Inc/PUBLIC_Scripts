# NetLock RMM

This directory is the public distribution point for N2con's signed NetLock RMM deployment scripts.

## Deployment model

- N2con maintains one preauthorized enrollment package per customer.
- A public deployment filename uses an opaque ID and does not reveal the customer name.
- The signed PowerShell wrapper accepts an approved local package or a fresh short-lived NetLock download URL, verifies the pinned hashes, and installs the agent into that customer's `Onboarding / Needs Placement` location.
- A technician moves the new device to its final location after enrollment.
- Internal Docmost documentation maps each customer to its approved script, one-liner, package expiration date, and operating procedure.

NetLock 3.2 package download tokens are short-lived. Public wrappers do not contain a durable enrollment URL or package ZIP. Tenant ZIPs are private release assets in `MSSP_Powershell_Signed` and are bundled with the wrapper for unattended deployment.

The `deploy/` directory will contain only final, signed scripts. It will not contain customer names, package-generation material, or unsigned drafts.

## Terminal use

Each deployment's internal Docmost entry provides its exact opaque wrapper and private package asset. For an interactive terminal install, obtain a fresh package URL from NetLock and pass it to the verified signed wrapper as `-PackageUrl`.

The standard command shape is:

```powershell
$u='<fresh-NetLock-package-url>';$p=Join-Path $env:TEMP 'n2c-netlock.ps1';try{Invoke-WebRequest 'https://raw.githubusercontent.com/N2con-Inc/PUBLIC_Scripts/main/NetLockRMM/deploy/<release-version>/n2c-nl-<deployment-id>-<release-version>.ps1' -OutFile $p -UseBasicParsing;$s=Get-AuthenticodeSignature -LiteralPath $p;if($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notlike 'CN=N2CON Inc.*'){throw "N2con signature validation failed: $($s.Status)"};& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -PackageUrl $u;if($LASTEXITCODE){exit $LASTEXITCODE}}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

`ExecutionPolicy Bypass` applies only to the child process after the downloaded file has passed explicit Authenticode validation. The command does not change the computer's configured execution policy.

For Intune, NinjaRMM, and GPO, keep the signed wrapper and its matching opaque ZIP together. The wrapper uses the adjacent ZIP automatically or accepts `-PackagePath`. Do not guess a deployment ID or package pairing.

## Other deployment tools

The same signed script can be used with:

- Microsoft Intune;
- Group Policy startup scripts;
- NinjaOne or another RMM;
- an elevated local PowerShell terminal; or
- another deployment system that runs PowerShell as an administrator or as `SYSTEM`.

Refer to N2con's internal technician and Intune guides for the approved command, detection rules, validation, and troubleshooting steps.
