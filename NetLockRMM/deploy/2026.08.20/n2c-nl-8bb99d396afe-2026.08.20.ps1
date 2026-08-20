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

$DeploymentId = '8bb99d396afe'
$DefaultPackageFileName = 'n2c-nl-8bb99d396afe-2026.08.20.zip'
$ExpectedZipSha256 = '6B9490EF362F7AD43214B5E07420AC155502C564AAD23C7DA184EB515326044E'
$ExpectedInstallerSha256 = '208EA0486B389FF3FCA5EEEFDAC6699F599D5E3760FB345C876EC7F686AF02DD'
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
# MII9HQYJKoZIhvcNAQcCoII9DjCCPQoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC96MF0cyg0WXSZ
# 7kdd1VwXk3b7SUthTsJvlfPjAdEoMqCCIeIwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# rRw+p+fL4WrxSK5nMYIakTCCGo0CAQEwcTBaMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQg
# VmVyaWZpZWQgQ1MgQU9DIENBIDA0AhMzAAUG9SagTM8PwNJRAAAABQb1MA0GCWCG
# SAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIDlHxkque8uE2yh+UZqYf9BmpXazq6hB
# kCoUTywKUR+oMA0GCSqGSIb3DQEBAQUABIIBgD3VmrUQO1puIFeeIQPs7laAFe/9
# KTACFVFEZ3WNL3bBfyXYknBPNq6+xA0kL3uXtdNZNLHr14LhFc7w2P8YuWsqqXrR
# FuiTBRDayHveEjJz4DvDFCazNF5TmwMH1oHGKlktMRNrD4gnDZdRdEvyL+h1Z8wp
# e4E11IuHzf1cnCCjVCif4cGfSFD14XkV7gaKnSfkdWDawSVdFMWlglQuaz271qES
# FfT7xvz20YZyemzcvqQ+3JYPatzJY+kazM29S9OcQRFYunlxE1stptTk494m+kKK
# R2NUcdO9eBOYeUtj9sr67zRfH9bN+xURRZxuqHb5tcVDGVuJfYGna/oHXH37eOwF
# cHjU21HwueoepQGYvHieFkiGMO6Dsu18PEZI7CP93W4koow8AvM5B+lXMPhW3zNM
# bNMHS04dDgoqTZztnqVycs4bhw+ZX9BAUOq9JTdBjIz2uT0jYcYdJeQT9IEyQ4ku
# Djx7VtLVn2Iefa2YR55/lYJPtUPB0enJ4SpBQKGCGBEwghgNBgorBgEEAYI3AwMB
# MYIX/TCCF/kGCSqGSIb3DQEHAqCCF+owghfmAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
# ggFiBgsqhkiG9w0BCRABBKCCAVEEggFNMIIBSQIBAQYKKwYBBAGEWQoDATAxMA0G
# CWCGSAFlAwQCAQUABCBConLudmuwK7tXTz2ZdcIXxcjiJeT1+7u+jVtdfyfDXwIG
# aoRsCW93GBMyMDI2MDgyMDIwMTQwMy45MTZaMASAAgH0oIHhpIHeMIHbMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3Nv
# ZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046
# N0EwMC0wNUUwLUQ5NDcxNTAzBgNVBAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
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
# AABYZc3rP6HX/NIAAAAAAFgwDQYJKoZIhvcNAQEMBQAwYTELMAkGA1UEBhMCVVMx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9z
# b2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwHhcNMjUxMDIzMjA0
# NjU1WhcNMjYxMDIyMjA0NjU1WjCB2zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdBMDAtMDVFMC1EOTQ3MTUwMwYD
# VQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0
# eTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJ14NKR2kOz1QJZZ/h2W
# ayRXC6Cm3pIVtci/kDQVIBRVLI2SCmqqjeKCCbCTN6bNKyTUju53QjUbmQ19loLq
# 9wJO+3l65aAV6mZjumVV3gzUQi5XVuANPzX48ye115HRIY6/NYIVxKUe8wvsG2jT
# frD0scywGQXomwxT+18LOcF9GbSLDdWtvl6uW71qd5ETMrcLJE47p0YHi2S/7Qad
# t+yVXUTxQEPY2ESqQqlAaP79cYwS0Qldz2pSo5xn29zDeFO41cqonxR0oXJ1uQhE
# UaAZlGurMoA8xUq/Ht4Pd0zzSxVIr1BNBpi321+XHg9RrdRXGesfyS1QE85OfgVh
# 2zMcCSFZFT06kkjI0OikynXJ6t6R9HOABSaf4Jb3KatFPX82SIyRhr3aYrIZUZe+
# 0ULVIUo8R7wp9ywv8akEMDh0kA7BoejV9g9EX7EshLUwAcgGnvtsNRwckw03JpUz
# SxLkC3go9YDQXSFo9FjmMg7Y40P/Ik1mOnstb2/ah5YyI+R4CJ3U+T/TGJNlYNnu
# 4SlGTQTWwP4bIAbLqGfiF/PVr4xDfWmxfdUuDiVbop5irCzvzC255e4pLg9HTeqA
# NGHsMg0J3LNdrDPRzrbu9kAP02ZXn71vK/cbTFwGKEJXBo7JPFuFHO3H6lamyD43
# aHPGcQcy3F3Fcj+KeXMi8L5DAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQUco1NxXq+
# FcVyfoYz3ESZ8Z0SCbAwHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEw
# bAYDVR0fBGUwYzBhoF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIw
# Q0ElMjAyMDIwLmNybDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVi
# bGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBm
# BgNVHSAEXzBdMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYG
# Z4EMAQQCMA0GCSqGSIb3DQEBDAUAA4ICAQB768SIlRdYh3F78ayUwg/HjrWz1Gyv
# cfi8+9ImHoYfhtFKDjHDH9OEA+rUD03meR4RhE5HJ9K2gyeTaX20QbihB99a8W2S
# ve6NdikQzSdzbuHj2lCKR/03Fs/Dy1TghAssEsWxIBBttJMsnRnOOnOfdbV86X5C
# Q3JI6GK8qWnq3XkC0UB/S2qE2GX3QMzKPg8tDtQ8xSZBeWJ7JgDPJbfa9TbV3RY3
# WxTAm1eXWruuJldtrNfOgPFJovpdt/flHtHGyUCMpFoSJYYVocUIKJLKh8+5Kdhh
# WQAHskk5iDkDlslzgPCQPEyEicp9yQzoErb+fNz91dEEgC0+iVwwltuhVdtPFRiT
# M5L9Ettojk2Sf6Gpk6ZPEcw/KFk/KX23tav5P28T4l2EW86bPemuWDpKO59FXaOt
# QziYS/5oZNNWN+PIKur4Rv1U3HRh4dawpMDjNOQd+QGWavQLT6X0cyYp6x88xkcf
# q+nw93HGDDzDF/zcHdoq866Yde9n0HEn9XzML8CIZnx+BliSfpn9RwOrl6ADlQcn
# JILl75Y/ID4u09hEukVPPkLLH6kzUySo7AYXlilr9luBElXp9i+5Qs+4u/RYQPtJ
# KdMlyZ2MHc1ktKL0yDVCyDZs1cjHElJuVrlX/GGd93ALndjqa+jdfkbi2Q2rw744
# noZSOXR/hhMuejGCB0Mwggc/AgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1Ymxp
# YyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjACEzMAAABYZc3rP6HX/NIAAAAAAFgw
# DQYJYIZIAWUDBAIBBQCgggScMBEGCyqGSIb3DQEJEAIPMQIFADAaBgkqhkiG9w0B
# CQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcNAQkFMQ8XDTI2MDgyMDIwMTQwM1ow
# LwYJKoZIhvcNAQkEMSIEIOrH/2ebNSXv2acR7TrxKV4DxuZIHfd0CVcY1vaNv1mn
# MIG5BgsqhkiG9w0BCRACLzGBqTCBpjCBozCBoAQgxSJUu7IH0PsAKNXFm1s/ljev
# VQXbOfIW62p/dfWi6HEwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBS
# U0EgVGltZXN0YW1waW5nIENBIDIwMjACEzMAAABYZc3rP6HX/NIAAAAAAFgwggNe
# BgsqhkiG9w0BCRACEjGCA00wggNJoYIDRTCCA0EwggIpAgEBMIIBCaGB4aSB3jCB
# 2zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMc
# TWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBU
# U1MgRVNOOjdBMDAtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3NvZnQgUHVibGlj
# IFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eaIjCgEBMAcGBSsOAwIaAxUAnWR5
# G9unq3BdjutrwnWVH1ErxFygZzBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1Ymxp
# YyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwDQYJKoZIhvcNAQELBQACBQDuMY2J
# MCIYDzIwMjYwODIwMTQyODI1WhgPMjAyNjA4MjExNDI4MjVaMHQwOgYKKwYBBAGE
# WQoEATEsMCowCgIFAO4xjYkCAQAwBwIBAAICEM8wBwIBAAICEnowCgIFAO4y3wkC
# AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEK
# MAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAZNuYZbJlU7KqSwCkxt9USQv9
# +cC+AHoKJ1tAEyMGpvjmF3kncBliBwWHsJ3m20wIymmvNHH7zzso1/jTuQli00et
# IJXRlJo2GXZGKjtcLR+yKO3DyMYnNOTw/kCpYe5q7RW7khhaUI/nxYuZhHWHrk5Z
# 92nSk36lCqgP1q7FfNtwdWXwZAJRgDdnt/EfV4caHp79B2fFbqcZE1E0VqIbBpNq
# 3XguF/Brn4v+lMVzjuuUtOA6u1SciQqIZTTuryGtZAbFM21XMI9EA3WaWv4p1xSg
# o0jPPVPf40mzU6Y8hs5G45O8MsuNhHDoSZVumHmV4qu47VZCDiL1Is1L+lsNXTAN
# BgkqhkiG9w0BAQEFAASCAgCcbt31PkCrc2vbMyidlRdBIZ87AhD7NkxRbC8FkewU
# BpqwqAQyGQT+098DQkVOiVWUD072xUU1Vht7EC/NaFt+hgdtUlIlaY4lfL3aG0ss
# br4SGePt05B+xWg2oDkHs/G4FSmnXRR2GpwOaRrZGcm43s3uPA2cQ8JChoP07BhP
# nZak9yuL4zmUZeptMPLzt1vy7fntgTG+vl2piXjKCn8ZmnIl/0/v9pU57tMddGy6
# skPxhmEVKt3ZPqpPtJH80gkqwppZSASDych01YtZKl7jmWwVx7+HCok2wzrs3EQp
# z6V4eNbfqc5q10hOrXY0JE3eQa+VdWyXy6Z8f71WYh9Hh0KuEP92z+ZiprOCngqa
# UYysLqUI40DnkirVIdYTa0uTN/Af8vDEWNoVEYdERcqr2UfN2dWqsgUPXqdrNf8I
# xG36mUcTKOxZEzkE+Qqlkl1Xn7wusgkNaI4BgE0FROI9TZB1ydCDRMmN/QENYUj5
# IxsLnYFfGiwX7V7wT/Q95WaJLNY5+vPQUY97yfXlJ8uDP4+GcbbqYpATblrRirXs
# cCZFgYLJgUryv53HiGcNtKbcZczfnVKvlOkG4jDEY0jUqEQekEcLX6ZfmDyTO95F
# 67WGdNRNmJ36sQzS03/TL8oh9fxMQE7cXlmvX6hSq9oeiusP9HYaLkA31xl3d74Z
# GA==
# SIG # End signature block
