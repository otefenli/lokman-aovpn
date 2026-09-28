<#
.SYNOPSIS
    Always On VPN SCCM / MECM Master Dağıtım Wrapper Betiği
.DESCRIPTION
    SCCM Application dağıtımlarında Device Tunnel, User Tunnel ve
    ağ/kriptografi sertleştirmelerini (PBK, NAT-T, IPsec Suite-B)
    otomatik olarak sırayla çalıştıran ana tetikleyici betiktir.
#>
[CmdletBinding()]
param ()

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Device Tunnel Kurulumu
$deviceXml = Join-Path (Split-Path -Parent $ScriptPath) "examples\DeviceTunnel.xml"
if (-not (Test-Path $deviceXml)) {
    $deviceXml = Join-Path $ScriptPath "DeviceTunnel.xml"
}

if (Test-Path $deviceXml) {
    Write-Host "[-] Device Tunnel kuruluyor..." -ForegroundColor Cyan
    & "$ScriptPath\Deploy-AovpnProfiles.ps1" -ProfileName "LHH-Device-Tunnel" -ProfileXmlPath $deviceXml
} else {
    Write-Warning "[-] DeviceTunnel.xml bulunamadı: $deviceXml"
}

# 2. User Tunnel Kurulumu
$userXml = Join-Path (Split-Path -Parent $ScriptPath) "examples\UserTunnel.xml"
if (-not (Test-Path $userXml)) {
    $userXml = Join-Path $ScriptPath "UserTunnel.xml"
}

if (Test-Path $userXml) {
    Write-Host "[-] User Tunnel kuruluyor..." -ForegroundColor Cyan
    & "$ScriptPath\Deploy-AovpnProfiles.ps1" -ProfileName "LHH-User-Tunnel" -ProfileXmlPath $userXml
} else {
    Write-Warning "[-] UserTunnel.xml bulunamadı: $userXml"
}

# 3. İstemci PBK, PlumbIKEv2TSAsRoutes=1, NAT-T ve IPsec Suite-B Sertleştirmesi
Write-Host "[-] İstemci ağ ve kriptografi sertleştirmesi uygulanıyor..." -ForegroundColor Cyan
& "$ScriptPath\Fix-AovpnIpv6Bypass.ps1"

Write-Host "[+] Always On VPN Master kurulum işlemi tamamlandı." -ForegroundColor Green
