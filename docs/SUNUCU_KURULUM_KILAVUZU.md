# Windows Server Always On VPN (RRAS + NPS + NAT) Kurulum ve Yapılandırma Kılavuzu

Bu doküman, Windows Server 2022 / 2025 üzerinde **Always On VPN (Device Tunnel ve User Tunnel)** sunucu altyapısını sıfırdan kurmak, NPS ile yetkilendirmek, IPsec Suite-B ile sertleştirmek ve RRAS Source-NAT mimarisiyle iç kaynaklara sorunsuz erişim sağlamak için teknik personele yönelik adım adım kılavuzdur.

---

## 📋 1. Ön Gereksinimler ve Planlama

### 1.1 Donanım ve Ağ Bilgileri
* **Sunucu Rolü:** Routing and Remote Access (RRAS), Network Policy Server (NPS).
* **Fiziksel / Sanal Ağ Kartı:** `Ethernet0`
  * **Sunucu Sabit IP:** `10.3.2.36 / 16`
  * **Varsayılan Ağ Geçidi (Gateway):** `10.3.2.1`
  * **Dahili DNS Sunucuları:** `10.3.2.11`, `10.3.2.10`
* **VPN İstemci Statik IP Havuzu:** `10.100.10.10` - `10.100.10.250` (Toplam 241 istemci adresi).
* **Dış Erişim FQDN:** `vpn.lhh.com.tr`

### 1.2 Dış Güvenlik Duvarı (Firewall) Port İzinleri
Dış firewall üzerinden VPN sunucusunun yerel IP'sine (`10.3.2.36`) aşağıdaki portlar yönlendirilmelidir (Port Forward / NAT):
* **UDP 500:** IKE (Internet Key Exchange)
* **UDP 4500:** IPsec NAT-Traversal (NAT-T)
* **TCP 443:** SSTP (Secure Socket Tunneling Protocol - Fallback amaçlı)

### 1.3 Sertifika Gereksinimleri
Sunucu üzerinde yerel makine deposunda (`LocalMachine\My`) geçerli bir VPN/SSL sertifikası bulunmalıdır:
* **Konu Adı (Subject / CN):** `vpn.lhh.com.tr`
* **Gelişmiş Anahtar Kullanımı (EKU):** Sunucu Kimlik Doğrulaması (`Server Authentication` - OID `1.3.6.1.5.5.7.3.1`)
* **Veren (Issuer):** Kurumsal CA (örn: `CN=LHH-CA, DC=lhh, DC=zone`)
* **Sertifika İptal Listesi (CRL):** Sunucu ve istemcilerin erişebileceği bir CDP noktası olmalıdır.

---

## 🛠️ 2. Rollerin Kurulumu

Yönetici haklarıyla açılmış bir PowerShell konsolunda gerekli Windows Server rollerini kurun:

```powershell
Install-WindowsFeature -Name RemoteAccess, DirectAccess-VPN, Routing, NPAS, RSAT-RemoteAccess, RSAT-NPAS -IncludeManagementTools
```

> **Not:** Kurulum tamamlandıktan sonra gerekiyorsa sunucuyu yeniden başlatın (`Restart-Computer`).

---

## ⚙️ 3. RRAS (Yönlendirme ve Uzaktan Erişim) Yapılandırması

### 3.1 GUI ile Başlatma ve Temel Yapılandırma
1. **Server Manager**'ı açın -> **Tools** -> **Routing and Remote Access** konsoluna girin.
2. Sunucu adına (örn: `GOKCE01`) sağ tıklayın ve **Configure and Enable Routing and Remote Access** seçeneğini tıklayın.
3. Karşılama sihirbazında **Custom Configuration** seçeneğini işaretleyip **Next** deyin.
4. Gelen ekranda şu seçenekleri işaretleyin:
   * ☑ **VPN access**
   * ☑ **LAN routing**
5. **Next** ve ardından **Finish** butonuna basın. Servisi başlatma uyarısına **Start service** diyerek onay verin.

---

### 3.2 VPN Sunucu Özelliklerinin Yapılandırılması
RRAS konsolunda sunucu adına sağ tıklayıp **Properties** ekranını açın:

#### A) General Sekmesi
* ☑ **IPv4 Router** (Seçenek: **Local area network (LAN) routing only**)
* ☑ **IPv4 Remote access server**

#### B) Security Sekmesi
* **Authentication Provider:** `Network Policy Server` (veya `Windows Authentication`)
* **Accounting Provider:** `Windows Accounting`
* **SSL Certificate Binding:** 
  * Açılır listeden `vpn.lhh.com.tr` için tanımlı sertifikayı seçin.

#### C) IPv4 Sekmesi
* **IPv4 address assignment:** `Static address pool` seçeneğini işaretleyin.
* **Add** butonuna basarak havuz aralığını ekleyin:
  * **Start IPv4 Address:** `10.100.10.10`
  * **End IPv4 Address:** `10.100.10.250`
* **Adapter:** `Ethernet0` kartını seçin (Sunucunun kurumsal ağ kartı).

#### D) IKEv2 Sekmesi
* **Idle timeout:** `300` saniye (varsayılan)
* **Network blackout time:** `1800` saniye (varsayılan)

Ayarları kaydedip çıkmak için **Apply** ve **OK** butonuna tıklayın. Gelen servis yeniden başlatma uyarısını onaylayın.

---

## 🔐 4. Sunucu Tarafı IPsec Suite-B Kriptografi Sertleştirmesi

Windows 11 Always On VPN istemcileriyle modern şifreleme el sıkışmasını (Suite-B standardı) zorunlu kılmak için PowerShell'i Yönetici olarak açın ve sunucuda şu komutu çalıştırın:

```powershell
Set-VpnServerIPsecConfiguration -AuthenticationTransformConstants SHA256128 `
    -CipherTransformConstants AES256 `
    -DHGroup Group14 `
    -EncryptionMethod AES256 `
    -IntegrityCheckMethod SHA256 `
    -PfsGroup PFS2048 -Force

# RRAS servisini yeniden başlatın
Restart-Service RemoteAccess -Force
```

| Parametre | Seçilen Değer | Açıklama |
| :--- | :--- | :--- |
| **CipherTransformConstants** | `AES256` | Veri şifreleme algoritması |
| **AuthenticationTransformConstants** | `SHA256128` | Paket bütünlüğü doğrulama |
| **DHGroup** | `Group14` (2048-bit) | IKE Faz 1 anahtar değişimi |
| **PfsGroup** | `PFS2048` | IKE Faz 2 (Child SA) Perfect Forward Secrecy |
| **EncryptionMethod** | `AES256` | Anahtar şifreleme |
| **IntegrityCheckMethod** | `SHA256` | IKE bütünlük kontrolü |

---

## 🛡️ 5. NPS (Network Policy Server) Yapılandırması

Kullanıcı tünelinin (User Tunnel) etki alanı kimlik bilgileriyle (EAP-MSCHAPv2) güvenle bağlanabilmesi için NPS politikası tanımlanmalıdır.

1. **Server Manager** -> **Tools** -> **Network Policy Server** konsolunu açın.
2. **NPS (Local)** -> **Policies** -> **Network Policies** yolunu izleyin.
3. Sağ tıklayıp **New** deyin:
   * **Policy name:** `Always On VPN User Tunnel`
   * **Type of network access server:** `Remote Access Server (VPN-IPsec)` -> **Next**.

4. **Specify Conditions (Koşullar):**
   * **Add** -> **User Groups:** VPN erişimi verilecek kurumsal güvenlik grubunu seçin (örn: `LHH\VPN_Users` veya test için `Domain Users`).
   * **Add** -> **NAS Port Type:** `Virtual (VPN)` seçin.
   * **Next** butonuna basın.

5. **Specify Access Permission:**
   * 🔘 **Access granted** seçin -> **Next**.

6. **Configure Authentication Methods:**
   * ☑ **Microsoft: Protected EAP (PEAP)** ekleyin.
     * Seçip **Edit** butonuna basın.
     * **Certificate issued:** Açılır listeden sunucu sertifikasını (`vpn.lhh.com.tr`) seçin.
     * **Eap Types:** `Microsoft: Secured password (EAP-MSCHAP v2)` seçili olmalıdır.
     * **OK** deyin.
   * Alttaki diğer tüm onay kutularını (MS-CHAP, PAP vb.) kaldırın. -> **Next**.

7. **Configure Constraints (Kısıtlamalar):**
   * **Idle Timeout:** 15-30 dakika (isteğe bağlı).
   * **Next** butonuna basın.

8. **Configure Settings (Ayarlar):**
   * **Encryption:** Yalnızca **Strongest encryption (MPPE 128-bit)** ve **Strong encryption** işaretli bırakın.
   * **Next** ve ardından **Finish** butonuna basarak sihirbazı tamamlayın.
9. Oluşturduğunuz `Always On VPN User Tunnel` kuralını listenin **en üstüne (Processing Order: 1)** taşıyın.

---

## 🌐 6. Sunucu Tarafı Source-NAT (SNAT / Connection Sharing)

### Neden Zorunludur?
VPN istemcileri `10.100.10.x` bloğundan IP aldığında, iç ağdaki web/portal sunucularına (`portal.lhh.com.tr` / `10.3.0.42`) erişebilir. Ancak merkez güvenlik duvarı/router üzerinde `10.100.10.0/24 -> 10.3.2.36` dönüş rotası tanımlanmadığı durumlarda yanıt paketleri düşer.

RRAS Source-NAT (SNAT) etkinleştirildiğinde, tüm istemci trafiği sunucunun kendi LAN IP'si (`10.3.2.36`) arkasında maskelenir ve iç ağdaki tüm kaynaklara anında erişim sağlanır.

### Yapılandırma Adımları:
Yönetici PowerShell konsolunda doğrudan hazırlanan otomasyon betiğini çalıştırın:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\lokman-aovpn\scripts\Configure-RrasNat.ps1" -LanInterfaceName "Ethernet0"
```

*Manuel Komut Eşdeğeri:*
```cmd
netsh routing ip nat install
netsh routing ip nat add interface name="Internal" mode=Private
netsh routing ip nat add interface name="Ethernet0" mode=Full
```

Doğrulamak için:
```cmd
netsh routing ip nat show interface
```
*Çıktıda `Ethernet0` için "Address and Port Translation", `Internal` için "Private Interface" görülmelidir.*

---

## 🔍 7. Sunucu Durum Doğrulama ve Teşhis

Kurulum tamamlandıktan sonra aşağıdaki komutlarla sunucu sağlığını kontrol edin:

```powershell
# 1. Dinlenen Portların Kontrolü
Get-NetUDPEndpoint -LocalPort 500, 4500
Get-NetTCPConnection -LocalPort 443 -State Listen

# 2. RRAS Sağlık Durumu
Get-RemoteAccessHealth

# 3. Aktif VPN Oturumları ve Trafik Sayaçları
Get-RemoteAccessConnectionStatisticsSummary

# 4. NPS Yetkilendirme Günlükleri (Son 1 saatteki başarılı oturumlar - Event 6272)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=6272; StartTime=(Get-Date).AddHours(-1)} -MaxEvents 5
```
