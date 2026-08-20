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

$DeploymentId = '136c2e84b0e0'
$DefaultPackageFileName = 'n2c-nl-136c2e84b0e0-2026.08.20.zip'
$ExpectedZipSha256 = 'ACF3DD31FAFB83B36DF3590EE009C6456DB85EE08F22638ADB26CD7299B3EB1B'
$ExpectedInstallerSha256 = '232B4E6E98A3099969150AC174211F7286912F7ABB52D0A2D32B00EB053FB173'
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
    Write-DeploymentMessage "The NetLock agent service already exists with status '$($existingService.Status)'. No installation is needed."
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
# MII9GwYJKoZIhvcNAQcCoII9DDCCPQgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAD91DTTGHVWm5/
# eTB+8gT/2oEDR96KAZtZ6c8jul1I+aCCIeIwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggaeMIIEhqADAgECAhMzAAUG9Sag
# TM8PwNJRAAAABQb1MA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBBT0MgQ0EgMDQwHhcNMjYwODE4MjIxMDMxWhcNMjYwODIx
# MjIxMDMxWjBgMQswCQYDVQQGEwJVUzETMBEGA1UECBMKQ2FsaWZvcm5pYTESMBAG
# A1UEBxMJU2FuIFJhbW9uMRMwEQYDVQQKEwpOMkNPTiBJbmMuMRMwEQYDVQQDEwpO
# MkNPTiBJbmMuMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAjW0bmqcv
# XXT0Yfovr0zlRBSQ8C1KH+jvK+4/lORdDpU/pDSofPwqWTUImBr3bJeaVeGxBvV+
# fCS0icmX4B0mhwKhqjI7Opj2O3m/JWoeh2x6rFJsHlI1qo2SefPe6HyI2HJnWsbl
# Ga13qOr9jQfaZUz/g1M9sVo+SrJyziFCq/wGs9Xc4bS6r5Vzkohn/Wgxk3kcnFCH
# W3KjT4Z6HzgNsI93ZZnH/8Xm6oqubSWx5LWoWs22XF7xnTJtNo8/EEPai/N0AHzS
# wSC3uTJP+mlmSPm0bNFHGiN/QLhxwa15T36lK9G/hK1EhtQOPnwlD8LaMUdqN2/4
# 1VG1D3NiuaLLXdvLKXN7aJJKrDviGw1G34Ihnwenix+oGmvmSU3eGdW1zKBnJmTo
# 10JBaDDRkZ1bV1zY+DzVVG7rlT5j1tUFMiSUHPenJctz3hMxb5rnwxUhodQG+YWa
# Qyr88IiXv9j1AWRTcl7vmNd4va0hUKQbVP5xYQ543Pto5MNbqef2LZi9AgMBAAGj
# ggHVMIIB0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAz
# BgorBgEEAYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2GCndftXIPT4fkX5NeyEoKh
# v/hRMB0GA1UdDgQWBBS53ABI5R2tLrB+fjmA6bA2ORY4eDAfBgNVHSMEGDAWgBRr
# JUHe+2t8/RiACi1/j3ZdqnM9uDBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlm
# aWVkJTIwQ1MlMjBBT0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYI
# KwYBBQUHMAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwQU9DJTIwQ0ElMjAwNC5j
# cnQwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG
# 9w0BAQwFAAOCAgEAIqwoMDTNToYjOesyy5xT/Lt3r6C6yjJrbphSnzbA8fLw09J4
# dQJ0uCDPP21jSCs7A4EnX1268Q4Xy9b/7yWoAuV1Q0m9K2sx04BjUlqz/yKOHD7R
# Mo4sjzYKShkTMJsz6LI/aBFyYNX3j6uGfBaKhjuJ24wr7NdqilAP71jvTZJYPdTc
# U6G9LEFVe2TkRJ0780uClxz4BfNxFAsh0rXLVes4gCEDo6MdFzUEFvenm597/0bH
# h5RvODE1lGqIRv0dljrVQ/D8f3NJZ9LXzyvRgeCrST/uqlK9DxAUz01hor+V+k7K
# 2v5G8788Wv4L8XXhUugdndj+o9xHHAuSylb0it02jeTrNcDNytK7pJKZsVg8jd63
# AaS+it4lRKYugR6HkelMBkETBhzMFSfHSK5G0imepDP4+Mk7vCPR6CVWwkOK76xC
# ub35OLlZtcbCmz+b991+j3WCedUiOdaQvFm524t7WSHCYTLKV1bcWBlwr4UqdbQL
# NUnlNwLbC96ITDJvzVdoODOR9rD/Rn61qV1PlE5Z+eyYcc5gHAp/1W1LsDoG9Cdx
# W21H1hQmNB+yF1L3NtaeSACCLyx7U2IQa41ii+UXtG9iiecYUsQgcSTF6FEZLLfo
# K2ExSb5sGnFbWsZOEC9E5VJNHhWwJyEIedz8ptgPbby2vIwY7OQsCeimXrcwggae
# MIIEhqADAgECAhMzAAUG9SagTM8PwNJRAAAABQb1MA0GCSqGSIb3DQEBDAUAMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBBT0MgQ0EgMDQwHhcNMjYw
# ODE4MjIxMDMxWhcNMjYwODIxMjIxMDMxWjBgMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKQ2FsaWZvcm5pYTESMBAGA1UEBxMJU2FuIFJhbW9uMRMwEQYDVQQKEwpOMkNP
# TiBJbmMuMRMwEQYDVQQDEwpOMkNPTiBJbmMuMIIBojANBgkqhkiG9w0BAQEFAAOC
# AY8AMIIBigKCAYEAjW0bmqcvXXT0Yfovr0zlRBSQ8C1KH+jvK+4/lORdDpU/pDSo
# fPwqWTUImBr3bJeaVeGxBvV+fCS0icmX4B0mhwKhqjI7Opj2O3m/JWoeh2x6rFJs
# HlI1qo2SefPe6HyI2HJnWsblGa13qOr9jQfaZUz/g1M9sVo+SrJyziFCq/wGs9Xc
# 4bS6r5Vzkohn/Wgxk3kcnFCHW3KjT4Z6HzgNsI93ZZnH/8Xm6oqubSWx5LWoWs22
# XF7xnTJtNo8/EEPai/N0AHzSwSC3uTJP+mlmSPm0bNFHGiN/QLhxwa15T36lK9G/
# hK1EhtQOPnwlD8LaMUdqN2/41VG1D3NiuaLLXdvLKXN7aJJKrDviGw1G34Ihnwen
# ix+oGmvmSU3eGdW1zKBnJmTo10JBaDDRkZ1bV1zY+DzVVG7rlT5j1tUFMiSUHPen
# Jctz3hMxb5rnwxUhodQG+YWaQyr88IiXv9j1AWRTcl7vmNd4va0hUKQbVP5xYQ54
# 3Pto5MNbqef2LZi9AgMBAAGjggHVMIIB0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB
# /wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEABggrBgEFBQcDAwYbKwYBBAGC
# N2GCndftXIPT4fkX5NeyEoKhv/hRMB0GA1UdDgQWBBS53ABI5R2tLrB+fjmA6bA2
# ORY4eDAfBgNVHSMEGDAWgBRrJUHe+2t8/RiACi1/j3ZdqnM9uDBnBgNVHR8EYDBe
# MFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
# b3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBBT0MlMjBDQSUyMDA0LmNybDB0
# BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENT
# JTIwQU9DJTIwQ0ElMjAwNC5jcnQwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYB
# BQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBv
# c2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEAIqwoMDTNToYjOesyy5xT/Lt3
# r6C6yjJrbphSnzbA8fLw09J4dQJ0uCDPP21jSCs7A4EnX1268Q4Xy9b/7yWoAuV1
# Q0m9K2sx04BjUlqz/yKOHD7RMo4sjzYKShkTMJsz6LI/aBFyYNX3j6uGfBaKhjuJ
# 24wr7NdqilAP71jvTZJYPdTcU6G9LEFVe2TkRJ0780uClxz4BfNxFAsh0rXLVes4
# gCEDo6MdFzUEFvenm597/0bHh5RvODE1lGqIRv0dljrVQ/D8f3NJZ9LXzyvRgeCr
# ST/uqlK9DxAUz01hor+V+k7K2v5G8788Wv4L8XXhUugdndj+o9xHHAuSylb0it02
# jeTrNcDNytK7pJKZsVg8jd63AaS+it4lRKYugR6HkelMBkETBhzMFSfHSK5G0ime
# pDP4+Mk7vCPR6CVWwkOK76xCub35OLlZtcbCmz+b991+j3WCedUiOdaQvFm524t7
# WSHCYTLKV1bcWBlwr4UqdbQLNUnlNwLbC96ITDJvzVdoODOR9rD/Rn61qV1PlE5Z
# +eyYcc5gHAp/1W1LsDoG9CdxW21H1hQmNB+yF1L3NtaeSACCLyx7U2IQa41ii+UX
# tG9iiecYUsQgcSTF6FEZLLfoK2ExSb5sGnFbWsZOEC9E5VJNHhWwJyEIedz8ptgP
# bby2vIwY7OQsCeimXrcwggcoMIIFEKADAgECAhMzAAAAFjGSjZICZXuaAAAAAAAW
# MA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjEwHhcNMjYwMzI2MTgxMTI5WhcNMzEwMzI2MTgx
# MTI5WjBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgQU9DIENBIDA0
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAylX6yNvoCTDP9G0OTlSj
# XbzgEsy21FDL17n/lZe2BrqHz2mR1aN4DBxeYp0/hjEqSHHyGfarV1NVBuvK8vLz
# W0LTi+DZt9In16aiNfgcogFiztWE9Fp8xu1zzrqE3nlrDWb+RZo8QrEXgWb8s8sw
# sl2W7tREHycVkx+Hm1MLQIlva6jH/Xg4/8GIYhHzbXiVd2RXomw9s7Qh6/SYRXXf
# e125wh4EKEyKnNNl+cZUSrVBgWvvjrRwQY4if7sAZ805KruBY6WY0Hiba5nWvrq9
# Qk9o35ViAf8qZ+7u1fbb1vcCWyWLfx9hLSdBjjVsSWe0xLvI1j4p3Tjt5czz+1Lc
# 0v5lQ1feB7nFmpbZrK2us0hvAaBCfOyDPEEm+735vzuNRYWJFL/PViI+REtjuJMc
# ojEn3veQjIrwrmK0T9oSr8e3oDzK1oAwwZMTC4KymTvYUTVDJvL5N8OW/UqIBzsi
# VYcchZvGhV3yMYKgxeEtIOG4W4Z85Y5kpQi5bpjGXFxRg46RdrTaALt1RhRmLR7U
# 0jVSr2aYAd2+Mp2qA5Gz3/loOOdt47eFZ3mrAYGYQtbK2SNjQpwgQX4Iy6tOKahC
# gFhKIcltitvSkpJB77eVWhNWnN2LfqMojszEue7V8EAySxry4PzlxTtFTb3Mw53X
# yH12BMQf2m9j7jEsHeVSATsCAwEAAaOCAdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQ
# BgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUayVB3vtrfP0YgAotf492XapzPbgw
# VAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMBAf8ECDAGAQH/AgEAMB8GA1UdIwQYMBaA
# FNlBKbAPD2Ns72nX9c0pnqRIajDmMHAGA1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVy
# aWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUF
# BwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNp
# Z25pbmclMjBQQ0ElMjAyMDIxLmNydDANBgkqhkiG9w0BAQwFAAOCAgEABtVQXlR0
# 1UQZY5XGQ9yIjMcD8jI0MizWhJ1buZjg5toUQSXx/BrASwE5qxwHPBeO45pOQp6V
# D4iILgm8OmfylY+A7KIqttvDUizC3sBXxjK4u7sDRiyEguXHKfL1HQAwxCLEtnRP
# kCPTsJA6b917lA+3foQIHC1XDDpdQLHxGbbGXp4Rr0mFK5vxbi6tAahBi/RlzOXP
# h6PavKPlZ/0vhlkDdsvoJETtebNJCNOZ1Kav3Tg+K4va4FbOrYqRHdGGahoA/gmT
# YmmVqw0zkGzT53HdhfajrFGttJomK7qE+T8CQGiPkEIkxNmSXjCTpDqc4U1IKlTG
# cGYnRFGSgqrnWnkANPFsJ5EDHysh82lPI+PFC3FOIVMLzLL+30rqznvRgHUUAj7x
# fFnEiuaAx3vFVSTOLb+iigpvdR6i8fSWpgYESOkdkn2N57tuhBs57tKwoP++vc/M
# VpuD1XAtmWi+lZSlahadTbDfGKjMn+bfm2xlW9PZ6BSnCRv1MMhpcUZkAZX3gVEM
# ef8rZc2c7BJ4ayRfX0wH43vI9znV+ZRJ3j0xUC0Zb82RQalF5yHkCr93x0IwvZtn
# 6P2dNQyCP6qd3fC4RlVFtAQhtOH0cByTR/Iqqghv6qHzL/pMptgMQQ5x8zYEYy+t
# CThYgYIrq7y4WEDYQfeSlqIxQOrIUJ4IJDEwggeeMIIFhqADAgECAhMzAAAAB4ej
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
# rRw+p+fL4WrxSK5nMYIajzCCGosCAQEwcTBaMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQg
# VmVyaWZpZWQgQ1MgQU9DIENBIDA0AhMzAAUG9SagTM8PwNJRAAAABQb1MA0GCWCG
# SAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIPKiTON+GPSwWKa2iWll5IfbeZQqSSt+
# 6QfVSSTwbEZ3MA0GCSqGSIb3DQEBAQUABIIBgFzHqHqhWHJDLj3FtqWqzJofimN8
# 90XoGzjQe9f4GSv5+vBng7SoL8xU+n5BFln6CdFzL23aPY//JuwUOYwh0qsgVu+M
# j9uV0GiBdLgEzi7Z6Hd5keVMAXtPihJhsPgxOhIDltwcrVuRx7wPNfxyk0m2zVUQ
# 5JH0buGi9lRbbUAJTOTc3w+Kl2qKMn9Ewzc0X47Y49+SrhtWb/Uv1gwPuDeDlTO2
# 9V6qICG4nkfg39iqNoiTRWuLB2XM5MbVSLXe6gU77I7f0+UKZFzq5H6oj34RCmHy
# bYO+GOu/c0ypSHrSlhAlgr+5wawhplsKWhcI2OHrUchP+aJGKs4d4GXLvnduD4zu
# Yz4iiOfPJuIKbaDvkPnEy/57BE41BL9tG97nHV0doPFSOeS231szDyI5EElEaKqN
# ftxn/bWBRkduPcgOm5RX6UR0W+xN529QERpyD+UoGJ6TGW0fjBiHejVax0UZP+zx
# ++GhqvNK99BIsZ6zZ5LXy0r2LMV4w8UgPAQCYaGCGA8wghgLBgorBgEEAYI3AwMB
# MYIX+zCCF/cGCSqGSIb3DQEHAqCCF+gwghfkAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
# ggFgBgsqhkiG9w0BCRABBKCCAU8EggFLMIIBRwIBAQYKKwYBBAGEWQoDATAxMA0G
# CWCGSAFlAwQCAQUABCBr9woi+RCYa9+ds+QpFJVbRcFEiq68MmP5rn7pylz46AIG
# aoSNEvNxGBEyMDI2MDgyMDE5NTQzMC45WjAEgAIB9KCB4aSB3jCB2zELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0
# IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjc4
# MDAtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1l
# IFN0YW1waW5nIEF1dGhvcml0eaCCDyEwggeCMIIFaqADAgECAhMzAAAABeXPD/9m
# LsmHAAAAAAAFMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDExMTkyMDMyMzFaFw0zNTExMTkyMDQyMzFaMGExCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAnnznUmP94MWfBX1jtQYioxwe1+eXM9ETBb1l
# Rkd3kcFdcG9/sqtDlwxKoVIcaqDb+omFio5DHC4RBcbyQHjXCwMk/l3TOYtgoBjx
# nG/eViS4sOx8y4gSq8Zg49REAf5huXhIkQRKe3Qxs8Sgp02KHAznEa/Ssah8nWo5
# hJM1xznkRsFPu6rfDHeZeG1Wa1wISvlkpOQooTULFm809Z0ZYlQ8Lp7i5F9YciFl
# yAKwn6yjN/kR4fkquUWfGmMopNq/B8U/pdoZkZZQbxNlqJOiBGgCWpx69uKqKhTP
# Vi3gVErnc/qi+dR8A2MiAz0kN0nh7SqINGbmw5OIRC0EsZ31WF3Uxp3GgZwetEKx
# Lms73KG/Z+MkeuaVDQQheangOEMGJ4pQZH55ngI0Tdy1bi69INBV5Kn2HVJo9XxR
# YR/JPGAaM6xGl57Ei95HUw9NV/uC3yFjrhc087qLJQawSC3xzY/EXzsT4I7sDbxO
# mM2rl4uKK6eEpurRduOQ2hTkmG1hSuWYBunFGNv21Kt4N20AKmbeuSnGnsBCd2cj
# RKG79+TX+sTehawOoxfeOO/jR7wo3liwkGdzPJYHgnJ54UxbckF914AqHOiEV7xT
# nD1a69w/UTxwjEugpIPMIIE67SFZ2PMo27xjlLAHWW3l1CEAFjLNHd3EQ79PUr8F
# UXetXr0CAwEAAaOCAhswggIXMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEE
# AwIBADAdBgNVHQ4EFgQUa2koOjUvSGNAz3vYr0npPtk92yEwVAYDVR0gBE0wSzBJ
# BgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/MB8GA1Ud
# IwQYMBaAFMh+0mqFKhvKGZgEByfPUBBPaKiiMIGEBgNVHR8EfTB7MHmgd6B1hnNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJ
# ZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1
# dGhvcml0eSUyMDIwMjAuY3JsMIGUBggrBgEFBQcBAQSBhzCBhDCBgQYIKwYBBQUH
# MAKGdWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNh
# dGUlMjBBdXRob3JpdHklMjAyMDIwLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAX4h2
# x35ttVoVdedMeGj6TuHYRJklFaW4sTQ5r+k77iB79cSLNe+GzRjv4pVjJviceW6A
# F6ycWoEYR0LYhaa0ozJLU5Yi+LCmcrdovkl53DNt4EXs87KDogYb9eGEndSpZ5ZM
# 74LNvVzY0/nPISHz0Xva71QjD4h+8z2XMOZzY7YQ0Psw+etyNZ1CesufU211rLsl
# LKsO8F2aBs2cIo1k+aHOhrw9xw6JCWONNboZ497mwYW5EfN0W3zL5s3ad4Xtm7yF
# M7Ujrhc0aqy3xL7D5FR2J7x9cLWMq7eb0oYioXhqV2tgFqbKHeDick+P8tHYIFov
# IP7YG4ZkJWag1H91KlELGWi3SLv10o4KGag42pswjybTi4toQcC/irAodDW8HNtX
# +cbz0sMptFJK+KObAnDFHEsukxD+7jFfEV9Hh/+CSxKRsmnuiovCWIOb+H7DRon9
# TlxydiFhvu88o0w35JkNbJxTk4MhF/KgaXn0GxdH8elEa2Imq45gaa8D+mTm8LWV
# ydt4ytxYP/bqjN49D9NZ81coE6aQWm88TwIf4R4YZbOpMKN0CyejaPNN41LGXHeC
# UMYmBx3PkP8ADHD1J2Cr/6tjuOOCztfp+o9Nc+ZoIAkpUcA/X2gSMkgHAPUvIdto
# SAHEUKiBhI6JQivRepyvWcl+JYbYbBh7pmgAXVswggeXMIIFf6ADAgECAhMzAAAA
# VyTTleCi6ckxAAAAAABXMA0GCSqGSIb3DQEBDAUAMGExCzAJBgNVBAYTAlVTMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29m
# dCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMB4XDTI1MTAyMzIwNDY1
# M1oXDTI2MTAyMjIwNDY1M1owgdsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3ODAwLTA1RTAtRDk0NzE1MDMGA1UE
# AxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCxbKUKkwh9uLMktjWQ9c7Z
# yZfYdFa9FsCZ4pJnl7Hv+MLKZ1XsRqn4hzaKpG1YOQop7mAvolXzTC2fkLaocks/
# FRgUo0bdSQeQAjbUygI35haeFPwr9i4+Jvr7r3vSN1t4UoiJkxbB3mGelf0neN61
# 64R1dun8N8UErXkm4Pck7Na4Xay5AI+CpiNA+T+Cmr7coIq1clFtdIJIn1i0hNTY
# gfCZ90TuXY99nXnjDTjWmj58N5OPSAk7NxX8m/npDQz7DX2MAqj8jk8TOstXUg9C
# eY/iivVfhFsleTw41fI459c7ErZUuk3GCSUrXIB7NsU/a7OqKFpeRbWH0ZAsYQ0o
# RKd7PCB1Fos01pi2bwBP+lkdgnfmZlWqRl0whySlAcmT8XV9IvIMp4q0fhMLhxzc
# RIpQyAi2rTtlmbvgkKx+GatDWKNU0OLVKWf5AFqaALta+JluRCdx5BGr0Nj7qEA3
# A6tqwBlSJWvaQ+6PWMcM5fNQbg71BMrvQ/+hdKpkA3WhO/dR8XwlMaYDGD6XVk87
# PnQxj3ocEPD/dsj/AEY28uTp8tWevEY3kHm6cX+Vi+ONZshR3IE9VCc84pe7TxJE
# dtjX0zUehZfo81m/6/NJ6pV5ZYcp0qMLcaNWNtsamL4ktuLJopFLASqjj20ku+7r
# 1xDt1axuSxqLhNRGdWPaYwIDAQABo4IByzCCAccwHQYDVR0OBBYEFI6DyV4tNQ4C
# CUhn5uNemIPtEpKnMB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwG
# A1UdHwRlMGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENB
# JTIwMjAyMC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1Ymxp
# YyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/
# BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYD
# VR0gBF8wXTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeB
# DAEEAjANBgkqhkiG9w0BAQwFAAOCAgEAcnXAdjzpmTlJQEM9jbl3+71glVpo1rvW
# 7GNfhzI79cni48Q0JI7CRFOc2iA8vFMPQWDfPhMV//ZP/QgVLF21ZW1OOHOuf5Ys
# ifN5FrBSFMIVWs8EkoRZWyGb4iDv+cHslsk3zz6W0iYFsvmRPVK0Et8bpSSwBwNs
# 1JDDD3QJReEa54HGWdK+OQBfWiGI3XrLVsHazSu9DHwKx6mXYK4F59N8OswbNb+3
# M3HlhorYPw5bB6pNZlwaUk7hiNk0jzdxOtCCF8eX/wBc4ePxxYvfAQWW1BCzbF5F
# gBvcp2eXughYopdZoFgljk/dA+yIL4NMynt6N1gpOtvf3p/eCv7Av8yzn9ne8hZk
# 8km/Xyo3DjR9Q295GfDMxCfHx0zZsa5ddBnnLs/xpdPgckyjfj2pm2fhdDCJQT8M
# On74xQvSSCO938N6jtevfvU8U89hvhNuhmGNXXH37AIcOg6k0IG35W5dTvzK0l0r
# NDUm/ZwQ/UX0f3/BIuwwNS9YwTu72YYSU48Nk8xWvwC4ES4t1tNIR1ovCxkGmXPE
# sFyDGFn8KzfTIGG4TdCGpPVgNnalrnpF7E8DZJqw9xOhPqAmAnoTToGZnbNBM29Y
# 6OzldCodti5dyh4NzB7ZRoLsQM4YPwaYsT0uKq1Cy5AIzu/sjbFH6w9lPYDH/zke
# MiQz7czNMrUxggdDMIIHPwIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMg
# UlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAVyTTleCi6ckxAAAAAABXMA0G
# CWCGSAFlAwQCAQUAoIIEnDARBgsqhkiG9w0BCRACDzECBQAwGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNjA4MjAxOTU0MzBaMC8G
# CSqGSIb3DQEJBDEiBCDs4tlG/eLgVZMZlyL+SM/oBLmR2zCQ09lxtaOmBrAL5jCB
# uQYLKoZIhvcNAQkQAi8xgakwgaYwgaMwgaAEIPU8n2S1BW5MZYhsos7h/VVQ6VRT
# b0BEISkNmYVMeNtSMHwwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNB
# IFRpbWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAVyTTleCi6ckxAAAAAABXMIIDXgYL
# KoZIhvcNAQkQAhIxggNNMIIDSaGCA0UwggNBMIICKQIBATCCAQmhgeGkgd4wgdsx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNT
# IEVTTjo3ODAwLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBS
# U0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHmiIwoBATAHBgUrDgMCGgMVAP0vMTmc
# QlEBQTZKzfFooo9cecvDoGcwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMg
# UlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMA0GCSqGSIb3DQEBCwUAAgUA7jGukzAi
# GA8yMDI2MDgyMDE2NDkyM1oYDzIwMjYwODIxMTY0OTIzWjB0MDoGCisGAQQBhFkK
# BAExLDAqMAoCBQDuMa6TAgEAMAcCAQACAgOCMAcCAQACAhIMMAoCBQDuMwATAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAKlSL+MT+ORS2yKZ9DRkSngiGQ7l
# Q4CZw9adBiGD1+18QOwcY3kuSSWhgw6wdkizUbbZjKwjZwQHBqZgMGY4V+2Sd+9y
# /PlJGWRR0pLYDQEruUJdJZEAgm87cckvScU18w45CUuS5xCw6iUFJZ3thR6AwJrz
# /qkLse0FGybvO88DYDPN0GuzuoXg7I0JAeUkaLgzUjF5IehXmIzHgFV7hkEm5xGq
# Yi7yE+Uh2Mc8inoVpvwTv1GFDZI2qXQVQJInCzarNp2zZ/G4wHQeQn8jDmFZB/Ai
# wpSCbY+6qMIgrTiI5s4DMOzFhlfAL+vKWLw0daw0It/OVI/x0fPzK7CKHUAwDQYJ
# KoZIhvcNAQEBBQAEggIAJTX4+fDzFcalXfYzdA6sMaytPR7/OrDEl+G6+onZ/gZJ
# RMeVcAuewrvd+WBuKscffyDfZdwNBJoHy91SfOccaRv43S6SX2sNQJnXNYAdT9eA
# stxJM79hE7L6EhliRFFicFMlAQaNrmXfNI/PJteBboCWUmjT2WcoYZXJ2EqGAzgb
# Q7MwM30afzsqECrxUt9nQqc66FTKhE94bJ3Bo4qRfULSEipvqWuM1jEPYdaGceux
# 9JcrmweN3wyZ3bzjEquXz/ytKe8itpdBOw9rbSCZ5XEpMLUH6lWhn923fapmTF7J
# MixUFl81EqJijbCmO4EEDe9vukxl7i+n/x6YuClbkAOVq9mSmmY5BQgZ8J+rXELi
# yUIwAl2kikHKvnzSCBL4lx4lHtkVTeWhXC2aWPhR58A2TT4LgnUiFGF+wkZ4jkEv
# E6gYt5v7bMnk5ubTCaaGX0FmJ8h6HR6PERplkYK4sl9FbpSBF48vFCOM4z9kNInB
# zPCCDxlm8+mNf2QLudL5WaE1OWqruhtA4CLytMdCa8xc37e7l43e1wr+c1kciGDA
# ng1lJJedq/j3cOBxwt5lKh/78dgwxtpYscE5L/1r0i92BuCXPwvC0LBqPWHXDjYs
# 0cty3rGy1xeHe1/FSvN1cF9Ks8QNiZiishAiYv6Bcqno2AQo8wnmBelPcchsk8o=
# SIG # End signature block
