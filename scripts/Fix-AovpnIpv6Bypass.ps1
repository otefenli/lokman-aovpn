<#
.SYNOPSIS
    Always On VPN İstemcisi IPv6CP Bypass, Error 628/623 Giderim ve IPsec Suite-B Sertleştirme Betiği
.DESCRIPTION
    IPv4-only kurumsal ağlarda Windows 11 Always On VPN (IKEv2) bağlantılarında
    INTERNAL_IP6_ADDRESS / IPv6CP kaynaklı Error 628 / 623 hatalarını engellemek,
    Traffic Selector rotalarını işlemek ve IPsec Suite-B kriptografi parametrelerini
    uygulamak için rasphone.pbk dosyalarını ve NAT-T kayıt defteri anahtarlarını yapılandırır.
#>
[CmdletBinding()]
param (
    [string[]]$ConnectionNames = @("LHH User Tunnel", "LHH-User-Tunnel", "LHH Device Tunnel", "LHH-Device-Tunnel")
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Bu betik Yönetici (Run as Administrator) olarak çalıştırılmalıdır!"
}

Write-Host "=== AOVPN İSTEMCİ AĞ VE KRİPTOGRAFİ SERTLEŞTİRMESİ ===" -ForegroundColor Cyan

# 1. NAT-T Registry Kaydı
$policyAgentPath = "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent"
Set-ItemProperty -Path $policyAgentPath -Name "AssumeUDPEncapsulationContextOnSendRule" -Value 2 -Type DWord -Force
Write-Host "[+] PolicyAgent AssumeUDPEncapsulationContextOnSendRule = 2 olarak ayarlandı." -ForegroundColor Green

# 2. IPsec Kriptografi Paketi (Suite-B Standardı: AES256, SHA256, Group14, PFS2048)
foreach ($conn in $ConnectionNames) {
    $existingConn = Get-VpnConnection -Name $conn -AllUserConnection -ErrorAction SilentlyContinue
    if (-not $existingConn) {
        $existingConn = Get-VpnConnection -Name $conn -ErrorAction SilentlyContinue
    }

    if ($existingConn) {
        try {
            Write-Host "[-] IPsec Suite-B uygulanıyor: $conn..." -ForegroundColor Cyan
            Set-VpnConnectionIPsecConfiguration -ConnectionName $conn `
                -AuthenticationTransformConstants SHA256128 `
                -CipherTransformConstants AES256 `
                -DHGroup Group14 `
                -EncryptionMethod AES256 `
                -IntegrityCheckMethod SHA256 `
                -PfsGroup PFS2048 -Force -ErrorAction Stop
            Write-Host "[+] $conn için IPsec Suite-B (PFS2048/Group14) başarıyla uygulandı." -ForegroundColor Green
        } catch {
            Write-Warning "[-] $conn için IPsec ayarlanamadı: $_"
        }
    }
}

# 3. PBK Dosyalarının Tespiti
$pbkFiles = @(
    "C:\ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk",
    "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk"
)

# Diğer kullanıcı profillerini de tara (User Tunnel için)
$userProfiles = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notmatch "^(Public|Default|All Users)$" }
foreach ($u in $userProfiles) {
    $userPbk = "$($u.FullName)\AppData\Roaming\Microsoft\Network\Connections\Pbk\rasphone.pbk"
    if ((Test-Path $userPbk) -and ($pbkFiles -notcontains $userPbk)) {
        $pbkFiles += $userPbk
    }
}

function Update-PbkContent {
    param ([string]$FilePath)

    if (-not (Test-Path $FilePath)) { return }

    Write-Host "[-] $FilePath dosyası düzenleniyor..." -ForegroundColor Yellow
    $content = Get-Content -Path $FilePath -Raw

    if ([string]::IsNullOrWhiteSpace($content)) { return }

    # 1. Ipv6Assign -> 0
    if ($content -match "(?m)^Ipv6Assign=") {
        $content = [regex]::Replace($content, "(?m)^Ipv6Assign=\d+", "Ipv6Assign=0")
    }
    if ($content -match "(?m)^IPv6Assign=") {
        $content = [regex]::Replace($content, "(?m)^IPv6Assign=\d+", "IPv6Assign=0")
    }

    # 2. IPv6AddressAssignmentMethod -> 0
    if ($content -match "(?m)^IPv6AddressAssignmentMethod=") {
        $content = [regex]::Replace($content, "(?m)^IPv6AddressAssignmentMethod=\d+", "IPv6AddressAssignmentMethod=0")
    }

    # 3. IPv6NameAssign -> 0
    if ($content -match "(?m)^IPv6NameAssign=") {
        $content = [regex]::Replace($content, "(?m)^IPv6NameAssign=\d+", "IPv6NameAssign=0")
    }
    if ($content -match "(?m)^Ipv6NameAssign=") {
        $content = [regex]::Replace($content, "(?m)^Ipv6NameAssign=\d+", "Ipv6NameAssign=0")
    }

    # 4. IpVersion -> 1 (IPv4 only)
    if ($content -match "(?m)^IpVersion=") {
        $content = [regex]::Replace($content, "(?m)^IpVersion=\d+", "IpVersion=1")
    }

    # 5. ExcludedProtocols -> 0
    if ($content -match "(?m)^ExcludedProtocols=") {
        $content = [regex]::Replace($content, "(?m)^ExcludedProtocols=\d+", "ExcludedProtocols=0")
    }

    # 6. ms_tcpip6 -> 0 (IPv6 bağlamını devre dışı bırak)
    if ($content -match "(?m)^ms_tcpip6=") {
        $content = [regex]::Replace($content, "(?m)^ms_tcpip6=\d+", "ms_tcpip6=0")
    }

    # 7. PlumbIKEv2TSAsRoutes -> 1 (Traffic Selector rotalarını otomatik işle)
    if ($content -match "(?m)^PlumbIKEv2TSAsRoutes=") {
        $content = [regex]::Replace($content, "(?m)^PlumbIKEv2TSAsRoutes=\d+", "PlumbIKEv2TSAsRoutes=1")
    } else {
        # Eğer yoksa her profil bloğuna ekle
        $content = [regex]::Replace($content, "(?m)(IpVersion=1)", "`$1`r`nPlumbIKEv2TSAsRoutes=1")
    }

    Set-Content -Path $FilePath -Value $content -Encoding ASCII -Force
    Write-Host "[+] $FilePath başarıyla güncellendi (IPv4-Only ve PlumbIKEv2TSAsRoutes=1 zorlandı)." -ForegroundColor Green
}

foreach ($pbk in $pbkFiles) {
    Update-PbkContent -FilePath $pbk
}

Write-Host "`n[+] Tüm PBK dosyaları, IPsec Suite-B ve NAT-T ayarları başarıyla tamamlandı." -ForegroundColor Cyan
