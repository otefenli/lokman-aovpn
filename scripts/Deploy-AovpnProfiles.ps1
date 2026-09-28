<#
.SYNOPSIS
    Windows 11 Always On VPN WMI Bridge Dağıtım Betiği
.DESCRIPTION
    WMI Bridge Provider (MDM_VPNv2_01) aracılığıyla Device Tunnel ve User Tunnel
    profillerini güvenli ve hatasız biçimde yükler, günceller veya kaldırır.
.PARAMETER ProfileName
    Yüklenecek VPN profilinin adı (örn. 'LHH-User-Tunnel' veya 'LHH-Device-Tunnel').
.PARAMETER ProfileXmlPath
    Yüklenecek ProfileXML dosyasının yolu.
.PARAMETER RemoveExisting
    Mevcut profili önce silip temiz kurulum yapar.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$ProfileName,

    [Parameter(Mandatory=$true)]
    [string]$ProfileXmlPath,

    [switch]$RemoveExisting = $true
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Bu betik Yönetici (Run as Administrator) olarak çalıştırılmalıdır!"
}

if (-not (Test-Path $ProfileXmlPath)) {
    throw "ProfileXML dosyası bulunamadı: $ProfileXmlPath"
}

# XML doğrulama ve Device/User tünel tespiti
$xmlRaw = Get-Content -Path $ProfileXmlPath -Raw
try {
    [xml]$xmlObj = $xmlRaw
} catch {
    throw "Geçersiz XML içeriği: $_"
}

$isDeviceTunnel = ($xmlObj.VPNProfile.DeviceTunnel -eq 'true')

# Bağlantı aktif mi kontrolü
$activeConn = Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue
if ($activeConn -and $activeConn.ConnectionStatus -eq 'Connected') {
    Write-Warning "[-] '$ProfileName' VPN bağlantısı şu anda aktif!"
    Write-Warning "[-] WMI Bridge kilitlenmesini (MI RESULT 1) önlemek için önce VPN bağlantısını kesmelisiniz."
    throw "VPN bağlantısı aktifken profil güncellenemez. Lütfen bağlantıyı kesip tekrar çalıştırın."
}

# OMA-DM ve XML kaçış (escape) karakterleri (WMI Bridge için zorunludur)
$profileNameEscaped = $ProfileName -replace ' ', '%20'
$escapedXml = $xmlRaw -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'

$namespace = "root\cimv2\mdm\dmmap"
$className = "MDM_VPNv2_01"
$cspUri = "./Vendor/MSFT/VPNv2"

# Temizlik (Mevcut profil)
try {
    $existing = Get-CimInstance -Namespace $namespace -ClassName $className -Filter "ParentID='$cspUri' and InstanceID='$profileNameEscaped'" -ErrorAction SilentlyContinue
    if ($existing -and $RemoveExisting) {
        Write-Host "[-] Mevcut profil WMI üzerinden siliniyor: $ProfileName" -ForegroundColor Yellow
        Remove-CimInstance -InputObject $existing -ErrorAction Stop
    }
} catch {
    Write-Verbose "Mevcut profil silinirken bilgi: $_"
}

Write-Host "[-] WMI Bridge üzerinden profil uygulanıyor: $ProfileName..." -ForegroundColor Cyan

$session = New-CimSession

try {
    $newInstance = New-Object Microsoft.Management.Infrastructure.CimInstance $className, $namespace
    $pParent = [Microsoft.Management.Infrastructure.CimProperty]::Create('ParentID', $cspUri, 'String', 'Key')
    $pInstance = [Microsoft.Management.Infrastructure.CimProperty]::Create('InstanceID', $profileNameEscaped, 'String', 'Key')
    $pXml = [Microsoft.Management.Infrastructure.CimProperty]::Create('ProfileXML', $escapedXml, 'String', 'Property')
    
    $newInstance.CimInstanceProperties.Add($pParent)
    $newInstance.CimInstanceProperties.Add($pInstance)
    $newInstance.CimInstanceProperties.Add($pXml)

    if ($isDeviceTunnel) {
        # Device Tunnel SYSTEM bağlamında uygulanır
        $session.CreateInstance($namespace, $newInstance) | Out-Null
    } else {
        # User Tunnel için kullanıcı SID bağlamı (PolicyPlatform_UserContext) zorunludur
        $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $options = New-Object Microsoft.Management.Infrastructure.Options.CimOperationOptions
        $options.SetCustomOption('PolicyPlatformContext_PrincipalContext_Type', 'PolicyPlatform_UserContext', $false)
        $options.SetCustomOption('PolicyPlatformContext_PrincipalContext_Id', "$userSid", $false)
        $session.CreateInstance($namespace, $newInstance, $options) | Out-Null
    }

    Write-Host "[+] Profil başarıyla kuruldu: $ProfileName" -ForegroundColor Green
} catch {
    Write-Error "[-] Profil oluşturulamadı ($ProfileName): $_"
    throw $_
} finally {
    if ($session) {
        Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
    }
}
