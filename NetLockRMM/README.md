# NetLock RMM

This directory is the public distribution point for N2con's signed NetLock RMM deployment scripts.

## Deployment model

- N2con maintains one preauthorized enrollment package per customer.
- A public deployment filename uses an opaque ID and does not reveal the customer name.
- The signed PowerShell wrapper downloads the approved NetLock installer package, verifies the pinned hashes, and installs the agent into that customer's `Onboarding / Needs Placement` location.
- A technician moves the new device to its final location after enrollment.
- Internal Docmost documentation maps each customer to its approved script, one-liner, package expiration date, and operating procedure.

The enrollment URL inside each public wrapper is intentionally usable without an N2con login. Its saved NetLock configuration is time-bounded, and the wrapper exposes only an opaque deployment ID. N2con can retire and replace the package if the URL is misused.

The `deploy/` directory will contain only final, signed scripts. It will not contain customer names, package-generation material, or unsigned drafts.

## Terminal use

Each deployment's internal Docmost entry provides its exact one-line PowerShell command. The command downloads the selected signed script, verifies its valid N2con Authenticode signature, runs that exact verified file, and removes the temporary copy.

The standard command shape is:

```powershell
$p=Join-Path $env:TEMP 'n2c-netlock.ps1';try{Invoke-WebRequest 'https://raw.githubusercontent.com/N2con-Inc/PUBLIC_Scripts/main/NetLockRMM/deploy/2026.08/n2c-nl-<deployment-id>-2026.08.ps1' -OutFile $p -UseBasicParsing;$s=Get-AuthenticodeSignature -LiteralPath $p;if($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notlike 'CN=N2CON Inc.*'){throw "N2con signature validation failed: $($s.Status)"};& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p;if($LASTEXITCODE){exit $LASTEXITCODE}}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

`ExecutionPolicy Bypass` applies only to the child process after the downloaded file has passed explicit Authenticode validation. The command does not change the computer's configured execution policy.

Do not guess a deployment ID. Use the command from the customer's internal documentation.

## Other deployment tools

The same signed script can be used with:

- Microsoft Intune;
- Group Policy startup scripts;
- NinjaOne or another RMM;
- an elevated local PowerShell terminal; or
- another deployment system that runs PowerShell as an administrator or as `SYSTEM`.

Refer to N2con's internal technician and Intune guides for the approved command, detection rules, validation, and troubleshooting steps.
