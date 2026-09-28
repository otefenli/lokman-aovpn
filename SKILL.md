---
name: windows-aovpn-deploy
description: >-
  Windows 11 Always On VPN (Device Tunnel + User Tunnel) dağıtımı, WMI Bridge (MDM_VPNv2_01)
  otomasyonu, IPsec Suite-B kriptografi sertleştirmesi, IPv4-only ortamlarda Hata 628/623 giderimi,
  rasphone.pbk ince ayarları ve 10.x.0.0/16 kurumsal rotalama standartları için operasyonel rehber ve araç seti.
---

# Windows 11 Always On VPN Dağıtım ve Yönetim Kılavuzu

Bu yetenek, Windows Server (RRAS + NPS) ve Windows 11 istemciler üzerinde Always On VPN (Device Tunnel ve User Tunnel) mimarisini güvenli, ölçeklenebilir ve kurumsal standartlara uygun olarak yapılandırmak için kullanılır.

---

## 1. Profil Türleri ve Kimlik Doğrulama Mimarisi

| Parametre | LHH Device Tunnel (Cihaz Tüneli) | LHH User Tunnel (Kullanıcı Tüneli) |
| :--- | :--- | :--- |
| **Kapsam** | Sistem Geneli (`AllUserConnection = $true`) | Kullanıcı Bazlı (`AllUserConnection = $false`) |
| **PBK Konumu** | `C:\ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk` | `%APPDATA%\Microsoft\Network\Connections\Pbk\rasphone.pbk` |
| **Bağlantı Zamanı** | Windows açılışında, oturum öncesi (**Pre-Logon**) | Kullanıcı oturum açtığında (**User Logon**) |
| **Kimlik Doğrulama** | Machine Certificate (Makine Sertifikası) | EAP-MSCHAPv2 (Type 26) / PEAP |
| **Kimlik Bilgisi** | Yerel Makine Sertifika Deposu (`LocalMachine\My`) | Windows Oturum Bilgisi (`UseWinlogonCredentials`) |
| **Kullanım Amacı** | DC iletişimi, Kerberos, GPO, SCCM, CRL kontrolleri | Kurumsal web uygulamaları, intranet ve dosya paylaşımları |
| **DNS Suffix** | `lhh.zone` | `lhh.com.tr` |

---

## 2. IPsec Kriptografi Paketi (Suite-B Standardı)

Her iki tünelin IKEv2 aşamasında RRAS sunucusuyla (`vpn.lhh.com.tr`) el sıkışabilmesi için profillere ve IPsec yapılandırmasına uygulanan Suite-B değerleri:

* **Authentication / Bütünlük:** `SHA256128` / `SHA256`
* **Şifreleme (Cipher / Encryption):** `AES256`
* **Diffie-Hellman Grubu (IKE Faz 1):** `Group14` (2048-bit)
* **PFS Grubu (IKE Faz 2 - Child SA):** `PFS2048` *(Sunucu tarafında zorunludur; None veya farklı grup seçildiğinde el sıkışma düşer)*

```powershell
Set-VpnConnectionIPsecConfiguration -ConnectionName "LHH User Tunnel" `
    -AuthenticationTransformConstants SHA256128 `
    -CipherTransformConstants AES256 `
    -DHGroup Group14 `
    -EncryptionMethod AES256 `
    -IntegrityCheckMethod SHA256 `
    -PfsGroup PFS2048 -Force
```

---

## 3. rasphone.pbk Çevirici ve Çekirdek Ağ Sertleştirmesi

Windows 11 (özellikle 24H2) üzerinde **Hata 628** ve **Hata 623** sorunlarını önlemek için PBK dosyalarında uygulanan parametreler:

1. **`IpVersion=1` (IPv4 Only):**  
   Windows istemcinin yalnızca IPv4 talep etmesini sağlar. IPv4-only çalışan RRAS sunucusuna istemcinin çift yığın (`INTERNAL_IP6_ADDRESS` / IPv6CP) paketi gönderip tüneli Hata 628 ile düşürmesini kesin olarak engeller.
2. **`Ipv6Assign=0` & `Ipv6NameAssign=0`:**  
   IPv6 adres ve DNS atama mekanizmalarını devre dışı bırakır.
3. **`PlumbIKEv2TSAsRoutes=1`:**  
   Split-tunneling sırasında sunucu tarafından dönen Traffic Selector'ların Windows yerel yönlendirme tablosuna (*routing table*) otomatik işlenmesini sağlar.
4. **`ExcludedProtocols=0`:**  
   EAP ve MS-CHAPv2 protokollerinin PBK düzeyinde filtrelenmesini/engellenmesini kaldırır.

---

## 4. Kayıt Defteri (Registry) Ayarları

* **NAT Traversal (NAT-T):**  
  İstemci veya VPN sunucusu NAT (güvenlik duvarı, ev modemi) arkasındayken IKEv2 / ESP paketlerinin UDP 4500 üzerinden sorunsuz kapsüllenmesi için:
  * **Kayıt Yolu:** `HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent`
  * **Değer Adı:** `AssumeUDPEncapsulationContextOnSendRule`
  * **Değer Türü / Veri:** `DWORD = 2`

---

## 5. Kurumsal Ağ ve Adresleme Standartları

* **Lokasyon Şablonu:** `10.x.0.0/16` (örn. x=0 Akay, x=1 Etlik, x=3 Genel Müdürlük / Gökçe, x=10 Depo vb.).
* **VPN İstemci Havuzu:** `10.100.10.10 - 10.100.10.250`.
* **Süpernet Yasağı:** Rota tanımlarında `10.0.0.0/8` kullanılmamalıdır. Kullanıcıların evlerindeki yerel ağlarla (`10.0.0.0/24`) çakışmayı önlemek için daima `/16` blokları rotalanmalıdır.
* **Omurga Dönüş Rotası (Return Route) ve RRAS NAT:**  
  * *Yöntem A (Statik Rota):* Merkez router/güvenlik duvarı üzerinde `10.100.10.0/24 -> [RRAS_LAN_IP]` rotası tanımlı ve tüm şubelere anons edilmiş olmalıdır.
  * *Yöntem B (RRAS NAT - Önerilen Hızlı Çözüm):* Merkez omurgada statik rota değişikliği yapılamıyorsa veya asimetrik firewall engellerini aşmak için RRAS üzerinde NAT etkinleştirilir:
    ```cmd
    netsh routing ip nat install
    netsh routing ip nat add interface name="Internal" mode=Private
    netsh routing ip nat add interface name="Ethernet0" mode=Full
    ```
    Bu sayede VPN istemcilerinin (`10.100.10.x`) iç ağa (`10.3.0.0/16`, `10.0.0.0/16` vb.) giden tüm trafiği RRAS LAN IP'si (`10.3.2.36`) üzerinden maskelenir (SNAT) ve iç kaynaklar (örn: `https://portal.lhh.com.tr`) sorunsuz yanıt döner.

---

## 6. WMI Bridge (`MDM_VPNv2_01`) ve XML Şema Sıralaması

WMI Bridge üzerinden `ProfileXML` enjekte edilirken Windows CSP şu katı XSD şema sırasını (`xs:sequence`) zorunlu kılar; sıra bozulursa `MI RESULT 1` hatası alınır:

1. `<DnsSuffix>`
2. `<RegisterDNS>`
3. `<NativeProfile>` (İçerisinde: `<Servers>`, `<RoutingPolicyType>`, `<NativeProtocolType>`, `<DisableClassBasedDefaultRoute>`, `<Authentication>`)
4. `<Route>` blokları

* **Örnek Device Tunnel XML:** [DeviceTunnel.xml](./examples/DeviceTunnel.xml)
* **Örnek User Tunnel XML:** [UserTunnel.xml](./examples/UserTunnel.xml)
* **Dağıtım Betiği:** [Deploy-AovpnProfiles.ps1](./scripts/Deploy-AovpnProfiles.ps1)
* **Onarım ve Sertleştirme Betiği:** [Fix-AovpnIpv6Bypass.ps1](./scripts/Fix-AovpnIpv6Bypass.ps1)
