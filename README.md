# NeYesem - Akıllı Yemek Platformu Toplayıcısı

**"Bugün ne yesem?" sorusuna akıllı ve bilinçli cevap.**

NeYesem, kullanıcıların yemek seçim kararlarını destekleyen, **platformlar arası fiyat ve kalori karşılaştırması** yapan, ardından kullanıcıyı Getir Yemek, Yemeksepeti veya Trendyol Yemek gibi partner uygulamalara **deep link** ile yönlendiren bir karar destek ve toplayıcı platformdur.

Uygulama **sipariş alma, sepet oluşturma, ödeme işleme veya teslimat takibi** yapmaz. Tüm ticari işlemler partner uygulamalar üzerinden gerçekleşir.

---

## 🎯 Proje Amacı ve Hedefleri

**Amaç:**  
Kullanıcılara en uygun fiyat, en sağlıklı seçenek ve en hızlı karar verme deneyimini sunmak.

**Hedefler:**
- Kişiselleştirilmiş AI yemek önerileri (geçmiş tercihler, konum, saat, diyet profili)
- Gerçek zamanlı fiyat karşılaştırması ve sahte indirim tespiti
- Kalori, makro besin ve alerjen takibi ile günlük hedef uyarıları
- Partner uygulamalara sorunsuz deep link yönlendirme
- MVP seviyesinde iOS & Android mobil uygulama + yönetim paneli

---

## 👥 Ekibimiz

NeYesem’i hayata geçiren yetenekli ve tutkulu ekip üyelerimiz.

### **FRONTEND EKİBİ**
- Fatma Nur Yazıcı  
- Mualla Gülsüm Çapar  

**Sorumluluklar:** Mobil uygulama arayüzü (Flutter), Ana Ekran, Keşif, Ürün Detayı, Yönlendirme ekranları ve state management.

### **BACKEND EKİBİ**
- Efekan Aksoy  
- Okan Aydınhan  
- Edem Makhsudov

**Sorumluluklar:** API Gateway, Auth Service, Partner Link Service, Search Service ve microservices mimarisi.

### **AI EKİBİ**
- Abdullah Çelik  
- Ahmet Yılmaz

**Sorumluluklar:** Recommendation Service (AI Öneri Motoru), kişiselleştirme algoritmaları, cold start mantığı ve geri bildirim sistemi.

### **DATABASE EKİBİ**
- Fuat Üzülmez  
- Abdullah Çelik  
- Edem Makhsudov

**Sorumluluklar:** PostgreSQL + TimescaleDB tasarımı, fiyat geçmişi zaman serisi, Nutrition Service ve veri optimizasyonu.

---

## 🛠 Kullanılan Teknolojiler

- **Frontend:** Flutter (iOS & Android)
- **Backend:** Node.js + Express (Microservices)
- **API Gateway:** Node.js / Express
- **Veritabanı:** PostgreSQL, TimescaleDB, Redis
- **Auth:** JWT + OAuth 2.0 (Google, Apple, Facebook)
- **AI:** Recommendation Service
- **Diğer:** Deep Link, Web Scraping/API entegrasyonları

---

## 📋 Benimsenen Yazılım Geliştirme Süreci

**Agile + Iterative** yaklaşım ile geliştiriyoruz:
- Scrum framework (2 haftalık sprintler)
- Gereksinim analizi: IEEE 830 standardına uygun **SRS v1.0**
- Tasarım: UML Use Case, Class ve Mimari Diyagramları
- Geliştirme: Feature Branch + Pull Request akışı
- Test: Unit, Integration ve Kullanım Senaryoları
- Dokümantasyon: Sürekli güncellenen README ve teknik dokümanlar

---

## 📚 Proje Dokümanları

- [Yazılım Gereksinim Dokümanı (SRS)](docs/NeYesem_SRS_v1_0.pdf)
- [Yazılım Tasarım Dokümanı](docs/NeYesem_Tasarim_Dokumani_v1.0.pdf)
- [Kullanım Kılavuzu](docs/NeYesem_Kullanim_Kilavuzu_v1.0.pdf)


**NeYesem** ile daha bilinçli ve ekonomik yemek kararları vermeye hazır mısınız?
