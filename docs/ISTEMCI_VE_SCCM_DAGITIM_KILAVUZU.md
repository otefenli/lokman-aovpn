# Windows 11 Always On VPN İstemci Kurulumu ve SCCM (MECM) ile Dağıtım Kılavuzu

Bu doküman; Windows 11 istemcilerde **Always On VPN (LHH Device Tunnel ve LHH User Tunnel)** profillerinin manuel olarak nasıl kurulacağını, IPsec Suite-B sertleştirmelerinin nasıl uygulanacağını ve yüzlerce/binlerce uç noktaya **Microsoft Endpoint Configuration Manager (SCCM / MECM)** kullanılarak nasıl otomatik olarak dağıtılacağını ve denetleneceğini (Compliance Baseline) adım adım anlatır.

---

## 🏛️ 1. İstemci Tünel Mimarisi ve Karşılaştırma

Always On VPN iki bağımsız tünelden oluşur:

| Parametre | LHH Device Tunnel (Cihaz Tüneli) | LHH User Tunnel (Kullanıcı Tüneli) |
| :--- | :--- | :--- |
| **Çalışma Bağlamı** | `NT AUTHORITY\SYSTEM` (Makine Düzeyi) | Oturum açan kullanıcı (`User Context`) |
| **PBK Konumu** | `C:\ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk` | `%APPDATA%\Microsoft\Network\Connections\Pbk\rasphone.pbk` |
| **Bağlantı Anı** | Windows açıldığında, oturum öncesi (**Pre-Logon**) | Kullanıcı Windows'a giriş yaptığında (**User Logon**) |
| **Kimlik Doğrulama** | Bilgisayar Sertifikası (`Machine Certificate`) | EAP-MSCHAPv2 (Etki alanı kullanıcı adı/şifre) |
| **Kullanım Amacı** | DC iletişimi, GPO, Kerberos, SCCM, DNS | İntranet, web uygulamaları (`portal.lhh.com.tr`), SMB |
| **DNS Suffix** | `lhh.zone` | `lhh.com.tr` |

---

## 💻 2. Manuel İstemci Kurulumu

İstemci üzerinde test veya tekil kurulum yapmak için aşağıdaki adımları sırayla takip edin:

### 2.1 Ön Hazırlık
Proje dosyalarını istemci makinede yerel bir dizine kopyalayın (örn: `C:\scripts\`):
* `Deploy-AovpnProfiles.ps1`
* `Fix-AovpnIpv6Bypass.ps1`
* `DeviceTunnel.xml`
* `UserTunnel.xml`

### 2.2 Tünel Profillerinin WMI Bridge Üzerinden Yüklenmesi
PowerShell'i **Yönetici olarak (Run as Administrator)** açın ve komutları çalıştırın:

```powershell
# 1. Device Tunnel Kurulumu (Pre-logon Makine Tüneli)
powershell.exe -ExecutionPolicy Bypass -File "C:\scripts\Deploy-AovpnProfiles.ps1" `
    -ProfileName "LHH-Device-Tunnel" `
    -ProfileXmlPath "C:\scripts\DeviceTunnel.xml"

# 2. User Tunnel Kurulumu (Kullanıcı Tüneli)
powershell.exe -ExecutionPolicy Bypass -File "C:\scripts\Deploy-AovpnProfiles.ps1" `
    -ProfileName "LHH-User-Tunnel" `
    -ProfileXmlPath "C:\scripts\UserTunnel.xml"
```

### 2.3 PBK, NAT-T ve IPsec Suite-B Sertleştirmesi
Windows 11 24H2 Hata 628/623 sorunlarını gidermek, `PFS2048` kriptografisini ve `PlumbIKEv2TSAsRoutes=1` ayarlarını uygulamak için:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\scripts\Fix-AovpnIpv6Bypass.ps1"
```

---

## 📦 3. SCCM (MECM) ile Otomatik Dağıtım Mimarisi

SCCM üzerinden dağıtım yaparken en kararlı ve standart yaklaşım **SCCM Application Modeli** kullanmaktır.

### 3.1 SCCM İçerik Kaynağının (Content Source) Hazırlanması
SCCM Site Server üzerinde paylaşılan kaynak klasörüne (örn: `\\sccm.lhh.zone\Sources\AOVPN\`) dağıtım paketini oluşturun:

```
\\sccm.lhh.zone\Sources\AOVPN\
├── Deploy-AovpnProfiles.ps1
├── Fix-AovpnIpv6Bypass.ps1
├── DeviceTunnel.xml
├── UserTunnel.xml
└── Install-AovpnMaster.ps1       # Ana yükleyici wrapper betiği
```

#### `Install-AovpnMaster.ps1` (Wrapper Script İçeriği):
```powershell
<#
.SYNOPSIS
    SCCM Always On VPN Master Kurulum Betiği
#>
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Device Tunnel Kur
& "$ScriptPath\Deploy-AovpnProfiles.ps1" -ProfileName "LHH-Device-Tunnel" -ProfileXmlPath "$ScriptPath\DeviceTunnel.xml"

# 2. User Tunnel Kur
& "$ScriptPath\Deploy-AovpnProfiles.ps1" -ProfileName "LHH-User-Tunnel" -ProfileXmlPath "$ScriptPath\UserTunnel.xml"

# 3. Sertleştirmeleri Uygula (PBK + NAT-T + IPsec Suite-B)
& "$ScriptPath\Fix-AovpnIpv6Bypass.ps1"
```

---

### 3.2 SCCM Üzerinde Application Oluşturma Adımları

1. **SCCM Konsolunu Açın:**
   * **Software Library** -> **Overview** -> **Application Management** -> **Applications**.
   * Sağ tıklayıp **Create Application** deyin.

2. **Genel Ayarlar:**
   * **Manually specify the application information** seçeneğini işaretleyip **Next** deyin.
   * **Name:** `Lokman Hekim Always On VPN`
   * **Publisher:** `LHH Bilgi Teknolojileri`
   * **Software Version:** `2.0` -> **Next**.

3. **Deployment Types (Dağıtım Türü):**
   * **Add** butonuna tıklayın.
   * **Type:** `Script Installer` seçip **Next** deyin.
   * **Name:** `Always On VPN Installer Script` -> **Next**.

4. **Content (İçerik) Ayarları:**
   * **Content location:** `\\sccm.lhh.zone\Sources\AOVPN\`
   * **Installation program:**
     ```cmd
     powershell.exe -ExecutionPolicy Bypass -File "Install-AovpnMaster.ps1"
     ```
   * **Uninstall program:**
     ```cmd
     powershell.exe -Command "Get-VpnConnection -AllUserConnection | Where-Object Name -like 'LHH*' | Remove-VpnConnection -Force; Get-VpnConnection | Where-Object Name -like 'LHH*' | Remove-VpnConnection -Force"
     ```
   * **Next** deyin.

5. **Detection Method (Algılama Kuralı):**
   SCCM'in uygulamanın kurulu olduğunu anlaması için PowerShell betiği kullanılır:
   * **Use a custom script to detect the presence of this deployment type** seçin.
   * **Edit Script** -> **Script Type:** `PowerShell`:
     ```powershell
     $device = Get-VpnConnection -Name "LHH-Device-Tunnel" -AllUserConnection -ErrorAction SilentlyContinue
     $user = Get-VpnConnection -Name "LHH-User-Tunnel" -AllUserConnection -ErrorAction SilentlyContinue
     if (-not $user) {
         $user = Get-VpnConnection -Name "LHH-User-Tunnel" -ErrorAction SilentlyContinue
     }

     # Her iki profil de mevcutsa SCCM kurulu kabul eder
     if ($device -and $user) {
         Write-Output "Installed"
     }
     ```
   * **OK** ve **Next** deyin.

6. **User Experience (Kullanıcı Deneyimi) - Kritik Ayarlar:**
   * **Installation behavior:** `Install for system` (Sistem için yükle)
   * **Logon requirement:** `Whether or not a user is logged on` (Kullanıcı oturumu açık olsun veya olmasın)
   * **Installation program visibility:** `Hidden` (Gizli / kullanıcıya pencere açılmaz)
   * **Maximum allowed run time:** `15` minutes
   * **Estimated installation time:** `2` minutes
   * **Next** -> **Next** -> **Close**.

7. **Dağıtım (Deploy):**
   * Oluşturulan uygulamaya sağ tıklayın -> **Deploy**.
   * **Collection:** Hedef bilgisayar koleksiyonunu seçin (örn: `All Windows 11 Laptops`).
   * **Deployment Settings:** Purpose = `Required` (Zorunlu kurulum).
   * **Scheduling:** `As soon as possible`.

---

## 🛡️ 4. SCCM Configuration Baseline (Compliance Settings) ile Sürekli Denetim

Kullanıcıların veya Windows güncellemelerinin PBK dosyasındaki `IpVersion=1` veya IPsec `PFS2048` ayarlarını bozmasını önlemek için bir **Configuration Item (CI)** ve **Baseline** tanımlanmalıdır.

### 4.1 Configuration Item (CI) Oluşturma
1. **Assets and Compliance** -> **Compliance Settings** -> **Configuration Items** -> **Create Configuration Item**.
2. **Name:** `CI - Always On VPN Client Settings`.
3. **Settings** sekmesinde **New** deyin:
   * **Name:** `Check-AOVPN-Compliance`
   * **Setting type:** `Script` | **Data type:** `Boolean`
   * **Discovery Script (PowerShell):**
     ```powershell
     $compliant = $true
     $pbkPath = "C:\ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
     if (Test-Path $pbkPath) {
         $content = Get-Content $pbkPath -Raw
         if ($content -notmatch "IpVersion=1" -or $content -notmatch "PlumbIKEv2TSAsRoutes=1") {
             $compliant = $false
         }
     }
     $reg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent" -Name "AssumeUDPEncapsulationContextOnSendRule" -ErrorAction SilentlyContinue
     if ($reg.AssumeUDPEncapsulationContextOnSendRule -ne 2) {
         $compliant = $false
     }
     return $compliant
     ```
   * **Remediation Script (Otomatik Onarım - PowerShell):**
     * `Fix-AovpnIpv6Bypass.ps1` içeriğini yapıştırın.
   * **Compliance Rules:** `Check-AOVPN-Compliance` rule = `True`.
   * ☑ **Run scripts and remediate noncompliant rules** (Uyumsuzluk durumunda betiği çalıştırıp düzelt) seçeneğini işaretleyin.

4. Bu CI'yı bir **Configuration Baseline** içerisine ekleyip haftalık/günlük olarak hedef koleksiyonlara dağıtın.

---

## 🔍 5. İstemci Test ve Sorun Giderme Adımları

### 5.1 Bağlantı Doğrulama
1. Windows ağ menüsünden **LHH-User-Tunnel** profiline tıklayıp **Bağlan (Connect)** deyin.
2. Bağlantı sağlandıktan sonra PowerShell konsolunda tünel rotalarını inceleyin:
   ```powershell
   Get-NetRoute -InterfaceAlias "*Tunnel*" -AddressFamily IPv4 | Format-Table DestinationPrefix, NextHop, RouteMetric
   ```
   *Çıktıda `10.3.0.0/16`, `10.0.0.0/16`, `10.100.0.0/16` rotalarının tünel arayüzüne atandığı görülmelidir.*

### 5.2 İç Kaynak Testi
Tarayıcınızı açarak kurumsal uygulamaları test edin:
* `https://portal.lhh.com.tr` (İç IP: `10.3.0.42`)
* Dahili DNS sunucusu testi: `Resolve-DnsName dc01.lhh.zone`

### 5.3 Olay Günlükleri (Event Viewer)
* **RasClient Olayları:** `Event Viewer` -> `Applications and Services Logs` -> `Microsoft` -> `Windows` -> `RasClient` -> `Operational`.
  * *Event 20227:* Başarılı bağlantı.
  * *Event 20226 / 20221:* Hata detayları (Hata kodu ve neden).
