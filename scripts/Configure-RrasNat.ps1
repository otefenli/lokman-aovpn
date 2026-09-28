<#
.SYNOPSIS
    RRAS Source-NAT (SNAT / Connection Sharing) Yapılandırma Betiği
.DESCRIPTION
    Windows Server Routing and Remote Access (RRAS) üzerinde Always On VPN istemcilerinin
    iç kurumsal ağdaki kaynaklara (portal, web, dosya sunucusu vb.) erişebilmesi için
    geri dönüş rotası (return route) ihtiyacını ortadan kaldıran IP NAT protokolünü kurar ve yapılandırır.
.PARAMETER LanInterfaceName
    Kurumsal yerel ağa bakan fiziksel ağ kartının adı (Varsayılan: 'Ethernet0').
#>
[CmdletBinding()]
param (
    [string]$LanInterfaceName = "Ethernet0"
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Bu betik Yönetici (Run as Administrator) olarak çalıştırılmalıdır!"
}

Write-Host "=== RRAS CONNECTION SHARING (NAT) KURULUMU ===" -ForegroundColor Cyan

# 1. Routing Protokollerini Kontrol Et
$protocols = netsh routing ip show protocol
if ($protocols -notmatch "Connection Sharing \(NAT\)") {
    Write-Host "[-] RRAS IP NAT protokolü kuruluyor..." -ForegroundColor Yellow
    netsh routing ip nat install | Out-Null
    Write-Host "[+] NAT protokolü başarıyla kuruldu." -ForegroundColor Green
} else {
    Write-Host "[+] NAT protokolü zaten kurulu." -ForegroundColor Green
}

# 2. Arayüzleri Kontrol Et ve Ekle
$currentNatIfaces = netsh routing ip nat show interface

# Internal (Private) Arayüzü
if ($currentNatIfaces -notmatch "NAT Internal Configuration") {
    Write-Host "[-] 'Internal' arayüzü Private modda ekleniyor..." -ForegroundColor Yellow
    netsh routing ip nat add interface name="Internal" mode=Private | Out-Null
    Write-Host "[+] 'Internal' arayüzü eklendi." -ForegroundColor Green
} else {
    Write-Host "[+] 'Internal' arayüzü zaten yapılandırılmış." -ForegroundColor Green
}

# LAN (Full / Address and Port Translation) Arayüzü
if ($currentNatIfaces -notmatch "NAT $LanInterfaceName Configuration") {
    Write-Host "[-] '$LanInterfaceName' arayüzü Full (Address and Port Translation) modda ekleniyor..." -ForegroundColor Yellow
    netsh routing ip nat add interface name="$LanInterfaceName" mode=Full | Out-Null
    Write-Host "[+] '$LanInterfaceName' arayüzü eklendi." -ForegroundColor Green
} else {
    Write-Host "[+] '$LanInterfaceName' arayüzü zaten yapılandırılmış." -ForegroundColor Green
}

Write-Host "`n=== GÜNCEL NAT YAPILANDIRMASI ===" -ForegroundColor Cyan
netsh routing ip nat show interface
Write-Host "`n[+] RRAS NAT yapılandırması başarıyla tamamlandı!" -ForegroundColor Green
