#requires -Version 5.1

<#
.SYNOPSIS
Installs an N2con-managed NetLock RMM agent.

.DESCRIPTION
Uses an approved local NetLock enrollment package or a supplied short-lived
download URL, verifies pinned SHA-256 hashes, installs the agent silently,
confirms the communication service exists, and removes temporary files. The
opaque deployment ID is mapped to a customer only in N2con's internal
documentation.
#>

[CmdletBinding()]
param(
    [string] $PackageUrl,
    [string] $PackagePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$DeploymentId = 'e8ead53c2001'
$DefaultPackageFileName = 'n2c-nl-e8ead53c2001-2026.10.22.zip'
$ExpectedZipSha256 = 'E286C41ADC848AFD9AFA16C1844A52026D9AABCE341166B04D1B6764E133ACA7'
$ExpectedInstallerSha256 = 'A16491FF5BB0A1158D8C24C23CEFAB6E7F9078DA643B8B9893FFE2B0889FAB6A'
$ServiceName = 'NetLock_RMM_Agent_Comm'
$SuccessfulInstallerExitCodes = @(0, 1641, 3010)

function Write-DeploymentMessage {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Output "[N2con NetLock][$DeploymentId] $Message"
}

if (-not $env:OS -or $env:OS -ne 'Windows_NT') {
    throw 'This deployment script must run on Windows.'
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this deployment as Local System or an elevated administrator.'
}

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    if ($existingService.Status -ne 'Running') {
        Start-Service -Name $ServiceName -ErrorAction Stop
        $existingService.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    }
    Write-DeploymentMessage 'The NetLock communication service is running. No reinstallation is needed.'
    exit 0
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) "N2con-NetLock-$([guid]::NewGuid().ToString('N'))"
$zipPath = Join-Path $stagingRoot 'NetLock-Agent.zip'
$extractPath = Join-Path $stagingRoot 'Extracted'

try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    if ($PackageUrl -and $PackagePath) {
        throw 'Supply PackageUrl or PackagePath, not both.'
    }

    if ($PackagePath) {
        $resolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
        Write-DeploymentMessage 'Using the supplied local enrollment package.'
        Copy-Item -LiteralPath $resolvedPackagePath -Destination $zipPath -Force
    }
    elseif ($PackageUrl) {
        Write-DeploymentMessage 'Downloading the approved enrollment package from the supplied short-lived URL.'
        Invoke-WebRequest -Uri $PackageUrl -OutFile $zipPath -UseBasicParsing
    }
    else {
        $adjacentPackagePath = Join-Path $PSScriptRoot $DefaultPackageFileName
        if (-not (Test-Path -LiteralPath $adjacentPackagePath -PathType Leaf)) {
            throw "Supply -PackagePath, supply a fresh -PackageUrl from NetLock, or place $DefaultPackageFileName beside this script."
        }
        Write-DeploymentMessage 'Using the enrollment package beside the signed wrapper.'
        Copy-Item -LiteralPath $adjacentPackagePath -Destination $zipPath -Force
    }

    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    if ($zipHash -ne $ExpectedZipSha256) {
        throw "Downloaded ZIP hash mismatch. Expected $ExpectedZipSha256; received $zipHash."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    $installers = @(Get-ChildItem -LiteralPath $extractPath -Filter 'NetLock_RMM_Agent_Installer.exe' -File -Recurse)
    if ($installers.Count -ne 1) {
        throw "Expected exactly one NetLock installer; found $($installers.Count)."
    }

    $installer = $installers[0]
    $installerHash = (Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash
    if ($installerHash -ne $ExpectedInstallerSha256) {
        throw "Installer hash mismatch. Expected $ExpectedInstallerSha256; received $installerHash."
    }

    Write-DeploymentMessage 'Package hashes are valid. Starting the silent installer.'
    $process = Start-Process -FilePath $installer.FullName -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -notin $SuccessfulInstallerExitCodes) {
        throw "NetLock installer returned exit code $($process.ExitCode)."
    }

    $installedService = $null
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $installedService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($installedService) {
            break
        }
        Start-Sleep -Seconds 5
    }

    if (-not $installedService) {
        throw "The installer completed, but service '$ServiceName' did not appear within 60 seconds."
    }

    if ($process.ExitCode -in @(1641, 3010)) {
        Write-DeploymentMessage "Installation succeeded and reported reboot-required exit code $($process.ExitCode)."
    }
    else {
        Write-DeploymentMessage "Installation succeeded. Service status: $($installedService.Status)."
    }
}
catch {
    Write-Error "NetLock deployment failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0

# SIG # Begin signature block
# MII9HQYJKoZIhvcNAQcCoII9DjCCPQoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4cvrH7W/nDxOV
# PAa5a3U0C8tYRDm45HqDPEJTDWwQCqCCIeIwggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggaeMIIEhqADAgECAhMzAAjnRM5h
# XiHSYD4KAAAACOdEMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDMwHhcNMjYxMDIxMTYzNDQxWhcNMjYxMDI0
# MTYzNDQxWjBgMQswCQYDVQQGEwJVUzETMBEGA1UECBMKQ2FsaWZvcm5pYTESMBAG
# A1UEBxMJU2FuIFJhbW9uMRMwEQYDVQQKEwpOMkNPTiBJbmMuMRMwEQYDVQQDEwpO
# MkNPTiBJbmMuMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAvZ5r1WUm
# mT06BbHbX5yK5MBEWxfccbCjU4MSD4zIBo4TfMvvKQOdi219GItMGWLyoIAM/2B/
# P2Q/Noa9vE4NfmkABZmN8Gi5lQg+p8lOR8Vhx01rtE6krUKKNXoxlDCwhI7dr4nJ
# iOmr/KhjPQYOs9e94WgakB6AsGp4B2HZOsecXjzf/JZqSbR30FcOnBq5jobQso0e
# M8IcJWxYj8j4rmqV9LcOjHnGFel3wB9ZPwCvbUN3TKA77e/pIUlb/LT2T/hmqOuv
# zgZuv5QveinCuz08tKOhjLZ8Pifgq+x1VzDH60cEANaIcq10fpXxmO5WGY8obQiG
# y4uPHBU+sTeVQfODrOOq08+/4OWegFj30PG9OGoYMOcvMRLy6KUhGLpuPb9e3iV2
# oH1GUop9vHp33NfzkSrAEfefGkIoV/jJonpmj3oT7oah+sOpD2JKmOaA6nJ7CDvG
# adgSFXnVQAcy6t9LbTCAvE/7NnxqNkxLCvzrttzWMRjD+47J34PGTz1nAgMBAAGj
# ggHVMIIB0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAz
# BgorBgEEAYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2GCndftXIPT4fkX5NeyEoKh
# v/hRMB0GA1UdDgQWBBSb2QbWl7k4yZDpTQqJqNDMW6yOkzAfBgNVHSMEGDAWgBRr
# XqU0wwXFYkohWo6rc2Bi1KxjhTBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlm
# aWVkJTIwQ1MlMjBFT0MlMjBDQSUyMDAzLmNybDB0BggrBgEFBQcBAQRoMGYwZAYI
# KwYBBQUHMAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwMy5j
# cnQwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG
# 9w0BAQwFAAOCAgEA1d3K4rs7hjAu0bc11oIAS52/aDJW3KIeLxUtNv2it9QtEDxP
# YfVTAEMk9GPugQmGqHOSK0/952b8bwa+NSaUFsa9tbM5awe8tTlrSX3xq38Exaei
# H5DIiHHS3XlZq1rHmQtZeniVdy9zilmWmS9QqgH1ViKOG1JkttnY2u2ugLKiAneN
# MZRrmfxgkXoUUdVupL+uv046F23vD4HIjs4KXnEAz0i4V8PcBXQ01cBzxdwOFfUb
# YCaLZO7I3AnA5zyLuGHg+lj4LgdIYIaRtBY8nevcDB0Nc0ketxUzdhbk6PrkxB4l
# ZioiuONBkcHQps1eVbB539wbco02kCeykQSmCT4hAIC7tE25QFBdXy5+gUlGkQmr
# q/Tg+VhM2yWZrXDaxaNuy5idZwPldlJYZu/w/0QhLIOqPxSAwbCsPW3i/JMnj/b7
# A8GWlAg6R2EBs2YnXhSnXkTGxsD61AJwMYNVkyPsXiuL4QRbssBBBhBbhAsvscQF
# xsgGO4525IxrV9+XJEoZEASZXdEmuxZqRGUr16t2kZg7I8cGztd2ds7+9Mmz1XDY
# Jjx+arJsRXnN7Cm1DwQY9wZC4XI9OVFw+3FZlWEE3JpYoI7lDZVMDd93KWKO91J/
# 3Q9xnOPmkRGYDBPlfYuSVeqtdXjCAuoN3VH9yKl1AOSPX6PdgYHCg+Y/0wMwggae
# MIIEhqADAgECAhMzAAjnRM5hXiHSYD4KAAAACOdEMA0GCSqGSIb3DQEBDAUAMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDMwHhcNMjYx
# MDIxMTYzNDQxWhcNMjYxMDI0MTYzNDQxWjBgMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKQ2FsaWZvcm5pYTESMBAGA1UEBxMJU2FuIFJhbW9uMRMwEQYDVQQKEwpOMkNP
# TiBJbmMuMRMwEQYDVQQDEwpOMkNPTiBJbmMuMIIBojANBgkqhkiG9w0BAQEFAAOC
# AY8AMIIBigKCAYEAvZ5r1WUmmT06BbHbX5yK5MBEWxfccbCjU4MSD4zIBo4TfMvv
# KQOdi219GItMGWLyoIAM/2B/P2Q/Noa9vE4NfmkABZmN8Gi5lQg+p8lOR8Vhx01r
# tE6krUKKNXoxlDCwhI7dr4nJiOmr/KhjPQYOs9e94WgakB6AsGp4B2HZOsecXjzf
# /JZqSbR30FcOnBq5jobQso0eM8IcJWxYj8j4rmqV9LcOjHnGFel3wB9ZPwCvbUN3
# TKA77e/pIUlb/LT2T/hmqOuvzgZuv5QveinCuz08tKOhjLZ8Pifgq+x1VzDH60cE
# ANaIcq10fpXxmO5WGY8obQiGy4uPHBU+sTeVQfODrOOq08+/4OWegFj30PG9OGoY
# MOcvMRLy6KUhGLpuPb9e3iV2oH1GUop9vHp33NfzkSrAEfefGkIoV/jJonpmj3oT
# 7oah+sOpD2JKmOaA6nJ7CDvGadgSFXnVQAcy6t9LbTCAvE/7NnxqNkxLCvzrttzW
# MRjD+47J34PGTz1nAgMBAAGjggHVMIIB0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB
# /wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEABggrBgEFBQcDAwYbKwYBBAGC
# N2GCndftXIPT4fkX5NeyEoKhv/hRMB0GA1UdDgQWBBSb2QbWl7k4yZDpTQqJqNDM
# W6yOkzAfBgNVHSMEGDAWgBRrXqU0wwXFYkohWo6rc2Bi1KxjhTBnBgNVHR8EYDBe
# MFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
# b3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBFT0MlMjBDQSUyMDAzLmNybDB0
# BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENT
# JTIwRU9DJTIwQ0ElMjAwMy5jcnQwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYB
# BQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBv
# c2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEA1d3K4rs7hjAu0bc11oIAS52/
# aDJW3KIeLxUtNv2it9QtEDxPYfVTAEMk9GPugQmGqHOSK0/952b8bwa+NSaUFsa9
# tbM5awe8tTlrSX3xq38ExaeiH5DIiHHS3XlZq1rHmQtZeniVdy9zilmWmS9QqgH1
# ViKOG1JkttnY2u2ugLKiAneNMZRrmfxgkXoUUdVupL+uv046F23vD4HIjs4KXnEA
# z0i4V8PcBXQ01cBzxdwOFfUbYCaLZO7I3AnA5zyLuGHg+lj4LgdIYIaRtBY8nevc
# DB0Nc0ketxUzdhbk6PrkxB4lZioiuONBkcHQps1eVbB539wbco02kCeykQSmCT4h
# AIC7tE25QFBdXy5+gUlGkQmrq/Tg+VhM2yWZrXDaxaNuy5idZwPldlJYZu/w/0Qh
# LIOqPxSAwbCsPW3i/JMnj/b7A8GWlAg6R2EBs2YnXhSnXkTGxsD61AJwMYNVkyPs
# XiuL4QRbssBBBhBbhAsvscQFxsgGO4525IxrV9+XJEoZEASZXdEmuxZqRGUr16t2
# kZg7I8cGztd2ds7+9Mmz1XDYJjx+arJsRXnN7Cm1DwQY9wZC4XI9OVFw+3FZlWEE
# 3JpYoI7lDZVMDd93KWKO91J/3Q9xnOPmkRGYDBPlfYuSVeqtdXjCAuoN3VH9yKl1
# AOSPX6PdgYHCg+Y/0wMwggcoMIIFEKADAgECAhMzAAAAFQU+bhmOkynZAAAAAAAV
# MA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjEwHhcNMjYwMzI2MTgxMTI4WhcNMzEwMzI2MTgx
# MTI4WjBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDAz
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA4PTLPQKqLw5zHj7zDnvi
# sm4QnfPpaJM2DkZUt5AVV7HnnG8hsAXLHp5ZuWy7TBj44iBS8wUBfoIZVVf1Nvau
# RnHXhBAQh00xoS9pKCKy3OFK5YjEXG7/ZjjLUf5e/8QJr9BceASR59XR7d+376wa
# l5ioynxn+Q6cjv/oZ1e0xK3jLUtfYjvm42f/R56YNzwpNHu2Em0UxZMfexWcEVqQ
# uLNzXqUX0V0If1jAI+yZrGHlWaIYuExecltiTKyWasB3MsyWWLQ9h5Z6OWRCZHYm
# XBGsRzqG5sDtOmdSfXNt6bPTxiIRmqtbCixAM/Q6HOay5GFhrXg67HCoQKdpCHP6
# GJR/SI+gZDqqoFiDRJBLQvGTRtTGpPod6OuWo9IkCpncVuyGWhzuXLsqDIvirWH1
# 3iCIN7FSG0thC/JFLbAxnRKjagKv4rKk4tY16i3uoiqdZ4tUj3bz1vRtNwk7GBev
# G/8riEEcG3aAQl3pjDSQktHaKwkWOG9lgAMuJ4O0gDXBIKwYGX+d+fkHy1OYRs6y
# oyKWzGm2rlm+RSllCpDLD3FxZF0VjuJ6Cj5uClpRcqajqWyfyjjVUXiJcR0EXoAD
# gcyIUQe4K/SA0NbHNjIDoEPsVRluKKuBw9JnwIsIsi7JGa5GkOyaGp2IwTXEfUUt
# umMQFW3AbS4rRU8wiBIOWXUCAwEAAaOCAdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQ
# BgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUa16lNMMFxWJKIVqOq3NgYtSsY4Uw
# VAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMBAf8ECDAGAQH/AgEAMB8GA1UdIwQYMBaA
# FNlBKbAPD2Ns72nX9c0pnqRIajDmMHAGA1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVy
# aWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUF
# BwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNp
# Z25pbmclMjBQQ0ElMjAyMDIxLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAXW4iPM8F
# y1/IJSRIf/ENtlDAlIVgTuOmfRT4cDkd5nZakVS5GDqJ/zHM1MK4w4cd1/fUjx+T
# 0n5ZBqE75zvWVhzOWBVWKTuzWLgfpn1UhgBmcIhjgElpNItge75/ZxJSSZqIl8bo
# Hx+WHQbK1IE7dABTV5M5qk4JPktR8W9bv9BwqhB1WT5NgP+niV2G7aUTORXM9NI4
# rFJfQUWYEnmzg1fOWwczr3qsgt39D5xwsUSTYTG/MT/7Af1SO6X9q4Xkle86lEr/
# L5/3yDG5V3mlSJaaqKvEj/QSTIxPwqFVycZ5GUETNRWu5Dfcs7b0XjocUoD4KWcf
# 15f45MMhBVSUwXwad7E4HyHP6Zqr9nobWpC9gBI+/BJjj0KIcSU98Ml/j+/BgNub
# S6QL8490TDB3fM9fGbrlYvutDAMxqTgEh9S/DZa932UWZ0Dvqcsntgwr2Jh2iH3V
# IGCap+56McRlb/PfkWhE4dbYAg78DaRQkhu75eQOGpKPtn8eNPa/U1o1wuzon9SE
# OWScweEX/BrwYh2I7zJh6ZXnadRRkS3UkRVaQt/ziqWWOmryKmae/vKT/1kD/dNw
# 3YK7wE+luMTzgcVz2uLRpLDd0rqiWohWB0jcngbn5/IrHro1uCGwUmxw+AT6mxd6
# mfu5xvXf3fxtvy8eJB/XApgX5rGXUpB5rpAwggeeMIIFhqADAgECAhMzAAAAB4ej
# NKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJ
# ZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkg
# MjAyMDAeFw0yMTA0MDEyMDA1MjBaFw0zNjA0MDEyMDE1MjBaMGMxCzAJBgNVBAYT
# AlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMTK01p
# Y3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCy8MCvGYgo4t1UekxJbGkIVQm0Uv96
# SvjB6yUo92cXdylN65Xy96q2YpWCiTas7QPTkGnK9QMKDXB2ygS27EAIQZyAd+M8
# X+dmw6SDtzSZXyGkxP8a8Hi6EO9Zcwh5A+wOALNQbNO+iLvpgOnEM7GGB/wm5dYn
# MEOguua1OFfTUITVMIK8faxkP/4fPdEPCXYyy8NJ1fmskNhW5HduNqPZB/NkWbB9
# xxMqowAeWvPgHtpzyD3PLGVOmRO4ka0WcsEZqyg6efk3JiV/TEX39uNVGjgbODZh
# zspHvKFNU2K5MYfmHh4H1qObU4JKEjKGsqqA6RziybPqhvE74fEp4n1tiY9/ootd
# U0vPxRp4BGjQFq28nzawuvaCqUUF2PWxh+o5/TRCb/cHhcYU8Mr8fTiS15kRmwFF
# zdVPZ3+JV3s5MulIf3II5FXeghlAH9CvicPhhP+VaSFW3Da/azROdEm5sv+EUwhB
# rzqtxoYyE2wmuHKws00x4GGIx7NTWznOm6x/niqVi7a/mxnnMvQq8EMse0vwX2Cf
# qM7Le/smbRtsEeOtbnJBbtLfoAsC3TdAOnBbUkbUfG78VRclsE7YDDBUbgWt75lD
# k53yi7C3n0WkHFU4EZ83i83abd9nHWCqfnYa9qIHPqjOiuAgSOf4+FRcguEBXlD9
# mAInS7b6V0UaNwIDAQABo4ICNTCCAjEwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQB
# gjcVAQQDAgEAMB0GA1UdDgQWBBTZQSmwDw9jbO9p1/XNKZ6kSGow5jBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoA
# UwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZ
# mAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsweaB3oHWGc2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZp
# Y2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5j
# cmwwgcMGCCsGAQUFBwEBBIG2MIGzMIGBBggrBgEFBQcwAoZ1aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUy
# MFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUy
# MDIwMjAuY3J0MC0GCCsGAQUFBzABhiFodHRwOi8vb25lb2NzcC5taWNyb3NvZnQu
# Y29tL29jc3AwDQYJKoZIhvcNAQEMBQADggIBAH8lKp7+1Kvq3WYK21cjTLpebJDj
# W4ZbOX3HD5ZiG84vjsFXT0OB+eb+1TiJ55ns0BHluC6itMI2vnwc5wDW1ywdCq3T
# Amx0KWy7xulAP179qX6VSBNQkRXzReFyjvF2BGt6FvKFR/imR4CEESMAG8hSkPYs
# o+GjlngM8JPn/ROUrTaeU/BRu/1RFESFVgK2wMz7fU4VTd8NXwGZBe/mFPZG6tWw
# kdmA/jLbp0kNUX7elxu2+HtHo0QO5gdiKF+YTYd1BGrmNG8sTURvn09jAhIUJfYN
# otn7OlThtfQjXqe0qrimgY4Vpoq2MgDW9ESUi1o4pzC1zTgIGtdJ/IvY6nqa80jF
# OTg5qzAiRNdsUvzVkoYP7bi4wLCj+ks2GftUct+fGUxXMdBUv5sdr0qFPLPB0b8v
# q516slCfRwaktAxK1S40MCvFbbAXXpAZnU20FaAoDwqq/jwzwd8Wo2J83r7O3onQ
# bDO9TyDStgaBNlHzMMQgl95nHBYMelLEHkUnVVVTUsgC0Huj09duNfMaJ9ogxhPN
# Thgq3i8w3DAGZ61AMeF0C1M+mU5eucj1Ijod5O2MMPeJQ3/vKBtqGZg4eTtUHt/B
# PjN74SsJsyHqAdXVS5c+ItyKWg3Eforhox9k3WgtWTpgV4gkSiS4+A09roSdOI4v
# rRw+p+fL4WrxSK5nMYIakTCCGo0CAQEwcTBaMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQg
# VmVyaWZpZWQgQ1MgRU9DIENBIDAzAhMzAAjnRM5hXiHSYD4KAAAACOdEMA0GCWCG
# SAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIDNdUf5CL3ivvzAvAQB4XLN5TCpoU0fl
# ql7gt/W2xRfPMA0GCSqGSIb3DQEBAQUABIIBgJRcM4dtw3axrXP7PYQVdVussdOc
# XADVFVBMm5mhD5fV2NWHclsbRjQboN3ZPfXelz9W0hUKUE0Fw3g9bqF9ifvdmeu2
# Cywa8VOlr7pRDNLEAc4v4VA9ePtjW3EHtjIUhj3lQmzhldhtqykOLsMyv4MvYDqD
# p3bhbNA1gdvmdTTkzgxCx3Z//TK4odcA6IgX0jgLhdGFLH2ihdq30JMe0dOe4ZT0
# g/NF7LO0okxxop+6yvcnTS4XBAsl06LYwH7pO0Ndm4YK7XbLnUvYirWsD9+I+o7K
# PrW1a5M0Tm0MlciC4o1nLbgKffBhkHg6HADBjP9GqJ6Jy2LjzCJ+4zGzsWNBvlcb
# yAji4ala43t3vGIj1ueH4nLTG+CDd6XldGau6MH0sakFVtF5ZJ3ze/hIBeow6oqU
# pxZHIk1/DMsTY9Eb5mtsatGdsTtuIE9jCzJRUuZpxNcbIELCWLnMbV7XUpwdwHGq
# 7gJ7iraEbSNUbCgK0eZvPuYwJB0ztlMIRU9FX6GCGBEwghgNBgorBgEEAYI3AwMB
# MYIX/TCCF/kGCSqGSIb3DQEHAqCCF+owghfmAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
# ggFiBgsqhkiG9w0BCRABBKCCAVEEggFNMIIBSQIBAQYKKwYBBAGEWQoDATAxMA0G
# CWCGSAFlAwQCAQUABCA+49fXqelHtMi6ltGa0d6V4esoQd/BcpZr0M4fxapN1wIG
# atf8po67GBMyMDI2MTAyMjIyNTk0NS40MTdaMASAAgH0oIHhpIHeMIHbMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3Nv
# ZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046
# NzgwMC0wNUUwLUQ5NDcxNTAzBgNVBAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWUgU3RhbXBpbmcgQXV0aG9yaXR5oIIPITCCB4IwggVqoAMCAQICEzMAAAAF5c8P
# /2YuyYcAAAAAAAUwDQYJKoZIhvcNAQEMBQAwdzELMAkGA1UEBhMCVVMxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjFIMEYGA1UEAxM/TWljcm9zb2Z0IElk
# ZW50aXR5IFZlcmlmaWNhdGlvbiBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAy
# MDIwMB4XDTIwMTExOTIwMzIzMVoXDTM1MTExOTIwNDIzMVowYTELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQCefOdSY/3gxZ8FfWO1BiKjHB7X55cz0RMF
# vWVGR3eRwV1wb3+yq0OXDEqhUhxqoNv6iYWKjkMcLhEFxvJAeNcLAyT+XdM5i2Cg
# GPGcb95WJLiw7HzLiBKrxmDj1EQB/mG5eEiRBEp7dDGzxKCnTYocDOcRr9KxqHyd
# ajmEkzXHOeRGwU+7qt8Md5l4bVZrXAhK+WSk5CihNQsWbzT1nRliVDwunuLkX1hy
# IWXIArCfrKM3+RHh+Sq5RZ8aYyik2r8HxT+l2hmRllBvE2Wok6IEaAJanHr24qoq
# FM9WLeBUSudz+qL51HwDYyIDPSQ3SeHtKog0ZubDk4hELQSxnfVYXdTGncaBnB60
# QrEuazvcob9n4yR65pUNBCF5qeA4QwYnilBkfnmeAjRN3LVuLr0g0FXkqfYdUmj1
# fFFhH8k8YBozrEaXnsSL3kdTD01X+4LfIWOuFzTzuoslBrBILfHNj8RfOxPgjuwN
# vE6YzauXi4orp4Sm6tF245DaFOSYbWFK5ZgG6cUY2/bUq3g3bQAqZt65KcaewEJ3
# ZyNEobv35Nf6xN6FrA6jF9447+NHvCjeWLCQZ3M8lgeCcnnhTFtyQX3XgCoc6IRX
# vFOcPVrr3D9RPHCMS6Ckg8wggTrtIVnY8yjbvGOUsAdZbeXUIQAWMs0d3cRDv09S
# vwVRd61evQIDAQABo4ICGzCCAhcwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcV
# AQQDAgEAMB0GA1UdDgQWBBRraSg6NS9IY0DPe9ivSek+2T3bITBUBgNVHSAETTBL
# MEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAUyH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsweaB3oHWG
# c2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIw
# QXV0aG9yaXR5JTIwMjAyMC5jcmwwgZQGCCsGAQUFBwEBBIGHMIGEMIGBBggrBgEF
# BQcwAoZ1aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNy
# b3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZp
# Y2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3J0MA0GCSqGSIb3DQEBDAUAA4ICAQBf
# iHbHfm21WhV150x4aPpO4dhEmSUVpbixNDmv6TvuIHv1xIs174bNGO/ilWMm+Jx5
# boAXrJxagRhHQtiFprSjMktTliL4sKZyt2i+SXncM23gRezzsoOiBhv14YSd1Kln
# lkzvgs29XNjT+c8hIfPRe9rvVCMPiH7zPZcw5nNjthDQ+zD563I1nUJ6y59TbXWs
# uyUsqw7wXZoGzZwijWT5oc6GvD3HDokJY401uhnj3ubBhbkR83RbfMvmzdp3he2b
# vIUztSOuFzRqrLfEvsPkVHYnvH1wtYyrt5vShiKheGpXa2AWpsod4OJyT4/y0dgg
# Wi8g/tgbhmQlZqDUf3UqUQsZaLdIu/XSjgoZqDjamzCPJtOLi2hBwL+KsCh0Nbwc
# 21f5xvPSwym0Ukr4o5sCcMUcSy6TEP7uMV8RX0eH/4JLEpGyae6Ki8JYg5v4fsNG
# if1OXHJ2IWG+7zyjTDfkmQ1snFOTgyEX8qBpefQbF0fx6URrYiarjmBprwP6ZObw
# tZXJ23jK3Fg/9uqM3j0P01nzVygTppBabzxPAh/hHhhls6kwo3QLJ6No803jUsZc
# d4JQxiYHHc+Q/wAMcPUnYKv/q2O444LO1+n6j01z5mggCSlRwD9faBIySAcA9S8h
# 22hIAcRQqIGEjolCK9F6nK9ZyX4lhthsGHumaABdWzCCB5cwggV/oAMCAQICEzMA
# AABeLhFuHHac7wUAAAAAAF4wDQYJKoZIhvcNAQEMBQAwYTELMAkGA1UEBhMCVVMx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9z
# b2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwHhcNMjYwOTE3MTg1
# NzIzWhcNMjcwOTE0MTg1NzIzWjCB2zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjc4MDAtMDVFMC1EOTQ3MTUwMwYD
# VQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0
# eTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANYLzn+RiTrerYIgiJrG
# pdKrEzaWWcXT2dAYG6E31aRl+HIkXj9Zazqhr90el4ioB6sXJKdqapzUSev3pnyD
# V94ncYrnrrTmETGuhnssH/l4SH7g2yzgb1or1QMCYKl6vXsY6aOD542hdEqwGirv
# hAn+ZC/4tIeaTliECBwiN1yVX/N+WQoZJi77gLyEODmpQB2hWKyhfDzZqpnOC36+
# jGNLdQXCgrU5LlSJSj+lTIyfHdr7lWZyE9xWkyyUIs3AAQtTgG92UfDD0AAg2H4F
# DrlfuVe/egzDu8kqS+DlaDHVXB+5hj+S1PnGOG9DlwVJVkUUA8OhdQ7i4xSJK8ID
# rZ1KsC5lXj35nfV8la9yTQK8dmFDlYYOdcGdCiZpdX7J7HxZIZaqP4cdjQn87zv9
# p+yH5bonjFU5pQIiJ9ZhS2dEYHYMPWJJyu8z3XliL/DdBgZivHeMp9OV6KczJwH0
# re8V1Xo5NmrXF3RrVQYtCKCRza/2ieuRt0PYkloaManzMG6a0d9ahxhDtiE11aQh
# Xrll/daZmHhBieScM97eYT4e+k0K3rAV96HfU6sVtGXip5LvJ3c7+PBDMkJYfQl/
# y/paM5nhW9wSEIAT8gYdGPRqKzolYdam9Gvst8XmHXkQbl6uUbMCxwA3U2CeN9vI
# h5Kval+7dBZsQ46Ls4jhpkBlAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQUkJ+O/e1c
# kFZIWyr7+tqwFespRu4wHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEw
# bAYDVR0fBGUwYzBhoF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIw
# Q0ElMjAyMDIwLmNybDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVi
# bGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBm
# BgNVHSAEXzBdMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYG
# Z4EMAQQCMA0GCSqGSIb3DQEBDAUAA4ICAQBFu/ZT4cvj4lM2inZbiG/mZywlkPod
# AKAk3ofp/uBe/Az6gmCAK5S3repNjtHt+cJpGGT1WDIJkrC0HhzcgTURxBWiHuwL
# rdArwPlIqQgHGNV0Ku6Y1UjsquXBMuT5fTVavpwqhDOgDdNDpxibvsN4IuY6AS2B
# htJQo5y23Ois6RUzzdyUbEdDql8Q8uG+KjkPHX9mBgdcszH2GCjvO5GONE+SpVFD
# UC/QiSj0LaPd1mEPBBYSPoah6uxvcvTcBf+wY4s2bu24WyaF+Avcm3wP7CI3wkgY
# bpVmINM7BH0c7oOTMlm/5WZXNflehbgPD4n1g6lNeTItfFEVf7j7aW/keozG7zoB
# vO9R3EWY6bJZ+dmpky3/1OdunEQsaeTHso4MNNQ0ODWBNeKHd8PEWEeihN4WxufO
# Tlu9J5luUQ8HO1FmVdClL07+6aYDWZ+ROTssgzv4QNeg3J3xr1SdR7Oou3l6CCFL
# 4AH6iTkjN1FwR9q67JFfmq53iaiEWJ7Bo3XCpoTM+WaQPMjixJA4Xx1+G6u06Eep
# TNi6ZJji3OW9KB2oQZdWoqaTevZRp6OoyDb2xPhQtKR9IDrttsDH6W0E0lW7n1si
# hsvRAIw3zyv6fw8D7GxmkP0VWtkSCyzXBbaR0RYXHEgUgnVYwXUwAa+YcudXxwJ+
# 16JlrnnC7vSDAzGCB0Mwggc/AgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1Ymxp
# YyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjACEzMAAABeLhFuHHac7wUAAAAAAF4w
# DQYJYIZIAWUDBAIBBQCgggScMBEGCyqGSIb3DQEJEAIPMQIFADAaBgkqhkiG9w0B
# CQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkFMQ8XDTI2MTAyMjIyNTk0NVow
# LwYJKoZIhvcNAQkEMSIEIJWi0a0DWgQ6/Fkt7k1DhxN2V938xDfYzzzSKPyv3DCL
# MIG5BgsqhkiG9w0BCRACLzGBqTCBpjCBozCBoAQg2fVmzDuHRgytmXR5bVL7Mwh0
# CGqqos+3kDbmXlBX7qMwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBS
# U0EgVGltZXN0YW1waW5nIENBIDIwMjACEzMAAABeLhFuHHac7wUAAAAAAF4wggNe
# BgsqhkiG9w0BCRACEjGCA00wggNJoYIDRTCCA0EwggIpAgEBMIIBCaGB4aSB3jCB
# 2zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMc
# TWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBU
# U1MgRVNOOjc4MDAtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3NvZnQgUHVibGlj
# IFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eaIjCgEBMAcGBSsOAwIaAxUA3q4d
# 2bA8fHDYjXY/C+auNvH/6AWgZzBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1Ymxp
# YyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwDQYJKoZIhvcNAQELBQACBQDuhHVl
# MCIYDzIwMjYxMDIyMTE0MzMzWhgPMjAyNjEwMjMxMTQzMzNaMHQwOgYKKwYBBAGE
# WQoEATEsMCowCgIFAO6EdWUCAQAwBwIBAAICE68wBwIBAAICEkgwCgIFAO6FxuUC
# AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEK
# MAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAKnjL665+6vGmQ0OaiLyAyfdX
# d6A5baYLTbpJwweXzVreoT6NDj4YSu2UBRsv3JOlZixz9OorlBIihZyftTGWF1Xc
# PqosUYD7HcuXjj62kX6lZYKGRwtqJ8OiPcsMCA7AkGivPo+zsC7nT5lu+Il49ZOy
# Eq3s9VJ04nq3j3zAO4X/wD0sUPyAvGWBd2kzfF84bHTcpdlgetsqiL6zjy4qDBh5
# R8QSHoxQaX3t9h4UMPVUfzwplQrRGkG2FqTVtKumdJU4V+g/oZBa9zsL+ScUA6/j
# GynhwD+xnL1Cl+fydPVuMlectMTzepYjTTSy0+3mzvrkUx9gsrVOZUZFeGKhijAN
# BgkqhkiG9w0BAQEFAASCAgCOkkfBaL2FZ35zBmbktj4rQhoGVpmHdDr4x88RHLnc
# MuB4ZNDV+tjkCSLPARcxRumOzln7w9vDZ835Xf/6c5t+n5H6aVwkzs4kJn4W1KsI
# UUbIvQxVqCMc5k1E1Axj9buVbC7DZnac6AhrfPRS2cAHcs7gBo6XDjVZ3UeTctST
# kDW5f6JWGDRqv6e99wKxFGfCq+HGq08M/opGwVo78Xw6ybWFTmVZQ7JRL8K/hlKl
# x5LeZaHEiwE2pJ3AKT9yAOS47mdYKEHOYyRudZ5S/FMgaYtCAwqYdLR45KBjWtHp
# dNpHTkSZYOpeKspyUsoT5h7y4Gh+hmpCbBPI1+5OZERD0Nv0e2wqH4hjSGkHw1hj
# rUjDHNJxqEx17Eu+KRmSX3thHLKNDrrbo2tb9q4fUlJk+LNk5iUHoHzQ6b8Q0seI
# 7d5MqVvwCpWu6EjltkRQvsqvO3q5wNRf6vzEN0r91OFqiw02zwbq/wbqonm3MR6H
# fXRj0ZDRnbER6TWOlbER4O7CSnDMKQgKc3lPK2xaDXleJk/275YZq2buLvKRjqLh
# Oj3wcQUyanblRAwmHMclh6aG1OyNW0ZK6J0Y7OhN6bSpAAd/9azMjiFRaOhOZBMR
# ngq0vl5ixVAX9SdP7WkY9ZBnWtQp9+UkUyVwNaHBdDKTURvuh3VSsSYGR3sTb/oL
# pw==
# SIG # End signature block
