# NetLock RMM

This directory is the public distribution point for N2con's signed NetLock RMM deployment scripts.

## Deployment model

- N2con maintains one preauthorized enrollment package per customer.
- A public deployment filename uses an opaque ID and does not reveal the customer name.
- The signed PowerShell wrapper downloads the approved NetLock installer package, verifies the pinned hashes, and installs the agent into that customer's `Onboarding / Needs Placement` location.
- A technician moves the new device to its final location after enrollment.
- Internal Docmost documentation maps each customer to its approved script, one-liner, package expiration date, and operating procedure.

The `deploy/` directory will contain only final, signed scripts. It will not contain customer names, package-generation material, or unsigned drafts.

## Terminal use

Each deployment's internal Docmost entry provides its exact one-line PowerShell command. The command downloads the selected signed script, verifies that its Authenticode status is `Valid`, runs it in an elevated PowerShell process, and removes the temporary copy.

Do not guess a deployment ID. Use the command from the customer's internal documentation.

## Other deployment tools

The same signed script can be used with:

- Microsoft Intune;
- Group Policy startup scripts;
- NinjaOne or another RMM;
- an elevated local PowerShell terminal; or
- another deployment system that runs PowerShell as an administrator or as `SYSTEM`.

Refer to N2con's internal technician and Intune guides for the approved command, detection rules, validation, and troubleshooting steps.
