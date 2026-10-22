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

$DeploymentId = '679e3bd4b97d'
$DefaultPackageFileName = 'n2c-nl-679e3bd4b97d-2026.10.22.zip'
$ExpectedZipSha256 = '54EB24187D8BCEF9BBE76AEAF30BDEDFAA43D8589BC9B09C9A9C08E0B7F2EC42'
$ExpectedInstallerSha256 = '9CBE7E69CA7825604F007AECA75447F7990BD492450B3388E18CB8E2B01D99F9'
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
# MII9HAYJKoZIhvcNAQcCoII9DTCCPQkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXr1sbkY2S475w
# W2KUIH6Zk1yhTxcZ7Q9EnpTcTQXt7aCCIeIwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# rRw+p+fL4WrxSK5nMYIakDCCGowCAQEwcTBaMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQg
# VmVyaWZpZWQgQ1MgRU9DIENBIDAzAhMzAAjnRM5hXiHSYD4KAAAACOdEMA0GCWCG
# SAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIPduMUHKOyK7/wPI9DiVhduT9Fp41RlM
# LRXFa5vlEQr2MA0GCSqGSIb3DQEBAQUABIIBgJ9RG9pG86pgxLoeyuAn9uQz74SL
# XPMfbdMUFaDXYf+XJ+oSTPYIDfKXbwoF6Mz3LKis3COV3qnFcrOnsGgdUzvTNsGL
# W9gFUh/aog6uRv4R2tZWm8H3iYxq81qKYpM2Zem8RaMP0TO+JfdpI/oM+bpySZ9e
# B7heKG2t+kS/OzAWl0ZBmazzq/gQDM+XA2FYODdv46AR5dobzVDjLgjtWgFKZF+d
# Hr5U3H7XSZeUramtxmv2E5KdKLIz3dVddM/cyQU8p1NQMpyWok6siTomO7/FGzOT
# W8o8UWYNHpcHi2eJXAOUTiCT8OrPp57/Pma9ant6Rl38ennlJV7nEIugWFdjXfnX
# /Dw61JV91/0XYpBriWmRWI5pcH3or36BMi3mxMN7etigtyrzkgQm1y7erV1Zbymh
# fHHWDTJ/mICEoSxtYynKR/uuZsnemuy8kyeoMkpGmz8hvm5Pt0N6LfSF173enWX/
# ZQVELie60q+++77Ejft1+gLGmJ4La+WJHvOrnqGCGBAwghgMBgorBgEEAYI3AwMB
# MYIX/DCCF/gGCSqGSIb3DQEHAqCCF+kwghflAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
# ggFhBgsqhkiG9w0BCRABBKCCAVAEggFMMIIBSAIBAQYKKwYBBAGEWQoDATAxMA0G
# CWCGSAFlAwQCAQUABCCbVG2UOoL+XhS55KLXtUaOj2uFvwH75alGPhec5NzV0gIG
# ateoX7ttGBIyMDI2MTAyMjIyNTA0Ny44NFowBIACAfSggeGkgd4wgdsxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29m
# dCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3
# QTAwLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGlt
# ZSBTdGFtcGluZyBBdXRob3JpdHmggg8hMIIHgjCCBWqgAwIBAgITMwAAAAXlzw//
# Zi7JhwAAAAAABTANBgkqhkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3NvZnQgSWRl
# bnRpdHkgVmVyaWZpY2F0aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIw
# MjAwHhcNMjAxMTE5MjAzMjMxWhcNMzUxMTE5MjA0MjMxWjBhMQswCQYDVQQGEwJV
# UzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
# b3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAJ5851Jj/eDFnwV9Y7UGIqMcHtfnlzPREwW9
# ZUZHd5HBXXBvf7KrQ5cMSqFSHGqg2/qJhYqOQxwuEQXG8kB41wsDJP5d0zmLYKAY
# 8Zxv3lYkuLDsfMuIEqvGYOPURAH+Ybl4SJEESnt0MbPEoKdNihwM5xGv0rGofJ1q
# OYSTNcc55EbBT7uq3wx3mXhtVmtcCEr5ZKTkKKE1CxZvNPWdGWJUPC6e4uRfWHIh
# ZcgCsJ+sozf5EeH5KrlFnxpjKKTavwfFP6XaGZGWUG8TZaiTogRoAlqcevbiqioU
# z1Yt4FRK53P6ovnUfANjIgM9JDdJ4e0qiDRm5sOTiEQtBLGd9Vhd1MadxoGcHrRC
# sS5rO9yhv2fjJHrmlQ0EIXmp4DhDBieKUGR+eZ4CNE3ctW4uvSDQVeSp9h1SaPV8
# UWEfyTxgGjOsRpeexIveR1MPTVf7gt8hY64XNPO6iyUGsEgt8c2PxF87E+CO7A28
# TpjNq5eLiiunhKbq0XbjkNoU5JhtYUrlmAbpxRjb9tSreDdtACpm3rkpxp7AQndn
# I0Shu/fk1/rE3oWsDqMX3jjv40e8KN5YsJBnczyWB4JyeeFMW3JBfdeAKhzohFe8
# U5w9WuvcP1E8cIxLoKSDzCCBOu0hWdjzKNu8Y5SwB1lt5dQhABYyzR3dxEO/T1K/
# BVF3rV69AgMBAAGjggIbMIICFzAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUB
# BAMCAQAwHQYDVR0OBBYEFGtpKDo1L0hjQM972K9J6T7ZPdshMFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# GQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAfBgNV
# HSMEGDAWgBTIftJqhSobyhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHegdYZz
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIw
# SWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBB
# dXRob3JpdHklMjAyMDIwLmNybDCBlAYIKwYBBQUHAQEEgYcwgYQwgYEGCCsGAQUF
# BzAChnVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jv
# c29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmlj
# YXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcnQwDQYJKoZIhvcNAQEMBQADggIBAF+I
# dsd+bbVaFXXnTHho+k7h2ESZJRWluLE0Oa/pO+4ge/XEizXvhs0Y7+KVYyb4nHlu
# gBesnFqBGEdC2IWmtKMyS1OWIviwpnK3aL5JedwzbeBF7POyg6IGG/XhhJ3UqWeW
# TO+Czb1c2NP5zyEh89F72u9UIw+IfvM9lzDmc2O2END7MPnrcjWdQnrLn1Ntday7
# JSyrDvBdmgbNnCKNZPmhzoa8PccOiQljjTW6GePe5sGFuRHzdFt8y+bN2neF7Zu8
# hTO1I64XNGqst8S+w+RUdie8fXC1jKu3m9KGIqF4aldrYBamyh3g4nJPj/LR2CBa
# LyD+2BuGZCVmoNR/dSpRCxlot0i79dKOChmoONqbMI8m04uLaEHAv4qwKHQ1vBzb
# V/nG89LDKbRSSvijmwJwxRxLLpMQ/u4xXxFfR4f/gksSkbJp7oqLwliDm/h+w0aJ
# /U5ccnYhYb7vPKNMN+SZDWycU5ODIRfyoGl59BsXR/HpRGtiJquOYGmvA/pk5vC1
# lcnbeMrcWD/26ozePQ/TWfNXKBOmkFpvPE8CH+EeGGWzqTCjdAsno2jzTeNSxlx3
# glDGJgcdz5D/AAxw9Sdgq/+rY7jjgs7X6fqPTXPmaCAJKVHAP19oEjJIBwD1LyHb
# aEgBxFCogYSOiUIr0Xqcr1nJfiWG2GwYe6ZoAF1bMIIHlzCCBX+gAwIBAgITMwAA
# AF3GOXhPQH0z/QAAAAAAXTANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3Nv
# ZnQgUHVibGljIFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjA5MTcxODU3
# MjFaFw0yNzA5MTQxODU3MjFaMIHbMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0EwMC0wNUUwLUQ5NDcxNTAzBgNV
# BAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAnfeo3PEUD4ms6oOxxnr5
# 0+xXsYIC89uEGj2MMjXhwsmk31IRN7u7diRWxUr1PfVqZUQSwpJ0NlB4Np5ImpQ2
# wio7MbAEu7GT9fw2VlGJBdanG87gNKKRr91ipU6R+HS2vsmGSAkX1uKg/LAuUttZ
# 9HMk4IZPt2jyP/UsUxNB8MEsDb+1jVODSksDGZytN2ImF85UbZ84sAGzkIwapHjV
# jLIOcI07nfunp/8psYD+l4G6TTV+QI9KyBKpHGg945xF5Bju8jo7auPPnHvMSj2h
# zGfnZKw8FlPqmAepuXClZRvpvtqHPLze6bgMLRIy9R/SGyb/T7723i9CavF5VxM1
# 1REBvBcNQtX1QvZ3zWqMPpk9u4sKgnacVVrB6V2+z1gl5PiaEbQ6k/7sii90m7bu
# yp1nhPxtVaup3up25vs0kAOaOJPOnzG4uZCsB0NH8+EENAWCDP6PzxLnVmbKJwdy
# dCRW0Q8qL+SyIdJXMrKx85c4MTNr0hmnjmatRWP8lMij6edIYWPLxIWx5dJOYn4a
# VEmF5GeFAoZRKxzPQw1jfUQnEA7xJ0+olpHbPfQbxi8k2BOLSlQzHR5vAa2q4X+X
# 7KPgXV/PRIOYJnUuKSqmk0Sy2LEkfBrfZ9v35qpv5QYFH8DWGvShGglZsBuJMIXV
# LIyT1siEJ89fYmAsMM39jM0CAwEAAaOCAcswggHHMB0GA1UdDgQWBBRD2wpdmU7w
# fh5W7f3lqGjIf1rnuTAfBgNVHSMEGDAWgBRraSg6NS9IY0DPe9ivSek+2T3bITBs
# BgNVHR8EZTBjMGGgX6BdhltodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBQdWJsaWMlMjBSU0ElMjBUaW1lc3RhbXBpbmclMjBD
# QSUyMDIwMjAuY3JsMHkGCCsGAQUFBwEBBG0wazBpBggrBgEFBQcwAoZdaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBQdWJs
# aWMlMjBSU0ElMjBUaW1lc3RhbXBpbmclMjBDQSUyMDIwMjAuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMGYG
# A1UdIARfMF0wUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAIBgZn
# gQwBBAIwDQYJKoZIhvcNAQEMBQADggIBAELIRPApwy7XbiTh4WhtQ6gKfJeKC1/p
# HJUNX+CMvvdgV8Feg7o4paA4m/pCs0+vNxB/LSQLrSzjZgJrhpRaATTi2ih2jaUc
# n12Kaxfa+BjVHMysfIYjGY9GhIlaZR1m+sPaktieppf8rIz/lX8+Wx7ozgaFEYnU
# 076R6tCbF3VxO5/BybUrXHMIMocNtQZ7eQtHcwE2wgotoGzmz0uU2gJiL7nWvl4f
# atCUctOWBCYOH90rTvdUON0+VtABpas/mhXurQypBVWbITPirdcHiEqAe2KcUHMC
# eazBsUvhHfIsQ0KxHeIPADpYJkVRNMxBCighDoitsHLQX74/4cIk8xKPo6CQ5eY1
# AUIuWY6DiXQ4FmjVOg+gIEMieDyOQiukmMTdMc6YK3kYH/XbyxkSUKzs6Gr8HkkB
# ZiU3syLke3CadevKdo/hFXSPZuLWWvV5hjo3ad8x4Pg3oWouH9vP+wmrrDzVKa/p
# nHRYRkCic+lJKCMc+4IFc8w9g5SCkoU+n4nCxgwCO68qPyacs1OGxlVq34wfwwdC
# ILMR7ctM5voCfP6r7G67X4PUfXW5DJwo6ZHed1zroRj4jIaxZ5L9INnuS9cValdw
# r+NYIm5nk5sQAJzBp7u6UbvyGbtWXYPNtx2Jvv8RNYTTzPqaFaJ2YzmaYOts5AbD
# vyRH2vNhyZNKMYIHQzCCBz8CAQEweDBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGlj
# IFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMAITMwAAAF3GOXhPQH0z/QAAAAAAXTAN
# BglghkgBZQMEAgEFAKCCBJwwEQYLKoZIhvcNAQkQAg8xAgUAMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAcBgkqhkiG9w0BCQUxDxcNMjYxMDIyMjI1MDQ3WjAv
# BgkqhkiG9w0BCQQxIgQggNag7VEErQHwGFL5cIVAjQ6s6qGoJ8Pxpr/lM8MqtpAw
# gbkGCyqGSIb3DQEJEAIvMYGpMIGmMIGjMIGgBCAtNWRLb+nz7kJioWWnRqK5hoUA
# Q15v3MvrF73cxAJKXTB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJT
# QSBUaW1lc3RhbXBpbmcgQ0EgMjAyMAITMwAAAF3GOXhPQH0z/QAAAAAAXTCCA14G
# CyqGSIb3DQEJEAISMYIDTTCCA0mhggNFMIIDQTCCAikCAQEwggEJoYHhpIHeMIHb
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046N0EwMC0wNUUwLUQ5NDcxNTAzBgNVBAMTLE1pY3Jvc29mdCBQdWJsaWMg
# UlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5oiMKAQEwBwYFKw4DAhoDFQC9p7q1
# tbGAzwdowGwPEcSazJaQ9aBnMGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGlj
# IFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDANBgkqhkiG9w0BAQsFAAIFAO6Eyd0w
# IhgPMjAyNjEwMjIxNzQzNTdaGA8yMDI2MTAyMzE3NDM1N1owdDA6BgorBgEEAYRZ
# CgQBMSwwKjAKAgUA7oTJ3QIBADAHAgEAAgIo/jAHAgEAAgISQTAKAgUA7oYbXQIB
# ADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQow
# CAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQAZWVcMEzxyREWI2JqmuEIdvfD8
# 1+NQkQ17It6wtgEKF9fyQijlnI5dwEjU7oat/stdZq0alqCsMhClhwq4HS+ybdS2
# SLPMOAWsPmXvPDyf+5b+3BEwc10h3ASpcbnaiQt5284hOQxbxR65FE6wJbOlgHTa
# 0rHADgLD0WXz1po73lCCx6v3eOXryCHbVu+yK/Q4G+SxFv2Qn++uEy5Xy4IhGnkK
# LcqIskYjUvR8dV+auPwEipc15v53JM6fSQs5IJqNnRy2jjg7vENBCFMiC2Jo5A1v
# RvRJqFgQ10hglTsVG1cWZ3oIZtSxdBY5IQLoMh2Zn2EqJzISz07+x1Xq05uwMA0G
# CSqGSIb3DQEBAQUABIICABrBUiYdwn5dsV9Wt6+SZasycKm3DfLjaGkktmK4K64P
# SU8tvrXN/zh4kuFY3LUN6o3k0HbN/P0IsA3QrIWbZYRvvBWYFpnoYKIUSOd5Szy9
# VVYMNdLc4AZz4o1ia6/Sjo/Wav3ReT5UxS7nDDXkBVSuvbqHqVDNeH3mHc2IZUcw
# 4SH/Z888sVtdj7xDCEqZtfRbpQM/Kzyg56nsxo6TRi146nf0/50frFmf8rlA5Q31
# l13VChUpK2ZRUElLVgvleFJwJ5aOvoAVwrFyS6vm7a7e3iVKXsZFofrq7w9QfCHO
# im2v08XP+2n2TsPXrHvbnslhSl0HAMiECzqKr3eVG9fRb3DNKtVwsZ0nnb0THY7W
# MC8sMK5paLoH+wNXzBNlJIG4rgK7yb+tP9hfVn6KJNln5OWkX4wYBT3hU+iV/Ve/
# 5jxmbU7J62/Ez0WJ0NeIw4/1/e/BbXtSCH+HkvKZZHl6iaiv3d6X2PGUUjK/xhPm
# +v/AWMtTqHKwxwjmAzUVmGpIrzOM/ZSaucx9yJohZCqyQLFkFZTEh2fH6y31VzhB
# ediLH+ZHQzA2o+67jv2/Lj+2oKRTTkp8jXFP8PNsO1iwSl7ptHDpLLBmue/x770x
# OqusKfKIIdiZe9w7L7V0UkpObIAtflRAMaDWs234D/gkQ5ZZNlsgLpTmZ7kiASee
# SIG # End signature block
