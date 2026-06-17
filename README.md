# NeYesem — Akıllı Yemek Platformu Toplayıcısı

> **"Bugün ne yesem?"** sorusuna akıllı ve bilinçli cevap.

NeYesem, Getir Yemek ve Yemeksepeti'ndeki yemekleri tek ekranda karşılaştıran, **sahte indirim tespiti** yapan ve kullanıcıyı doğrudan partner uygulamaya yönlendiren bir karar destek platformudur. Uygulama sipariş alma, sepet veya ödeme **yapmaz** — tüm ticari işlemler partner uygulamalar üzerinden gerçekleşir.

---

## 🚀 Hızlı Başlangıç

Tam kurulum rehberi için → **[KURULUM.md](KURULUM.md)**

```powershell
# 1) Veritabanı (PostgreSQL gerekli)
createdb -U postgres ne_yesem
psql -U postgres -d ne_yesem -f database/schema.sql

# 2) Örnek veri yükle
cd database; pip install -r requirements.txt
$env:DB_PASSWORD="<SIFRE>"; $env:PYTHONIOENCODING="utf-8"
python json_to_db.py --yemeksepeti ../backend/data/restaurants.json --sehir bursa
python json_to_db.py --folder ../backend/data/getir_output/output/bursa/getir_yemek --sehir bursa
cd ..

# 3) Backend (.env oluştur: USE_DB=true + DB_PASSWORD)
cd backend; npm install; npm start

# 4) Mobil uygulama (yeni terminal)
cd mobile; flutter pub get; flutter run
```

> **DB olmadan da çalışır:** `backend/.env` dosyasında `USE_DB=false` yapın — veri `backend/data/` klasöründeki JSON'lardan okunur.

---

## 🎯 Özellikler

| Özellik | Açıklama |
|---------|----------|
| 🔍 **Ürün Arama** | Türkçe karakter desteğiyle tüm platformlarda eş zamanlı arama |
| 💰 **Fiyat Karşılaştırma** | Aynı ürün için Getir & Yemeksepeti fiyatlarını yan yana listele |
| 🚨 **Sahte İndirim Tespiti** | Piyasa ortalamasıyla karşılaştırarak şüpheli indirimleri işaretle |
| 📍 **Otomatik Konum** | Sunucu taraflı IP tespiti → GPS ile ilçe refinement |
| 👤 **Kullanıcı Profili** | Alerjen takibi, diyet tercihi, kalori hedefi |
| 🔗 **Deep Link** | Partner uygulamayı tek dokunuşla aç |

---

## 🏗 Mimari

```
project/
├── backend/          # Node.js + Express REST API
│   ├── src/app.js    # Tek dosya API (endpoints, analiz, cache)
│   └── data/         # JSON veri dosyaları (DB olmadan kullanılır)
├── mobile/           # Flutter uygulaması (iOS & Android)
│   └── lib/main.dart # Tek dosya uygulama
├── database/         # PostgreSQL şema + veri yükleme scripti
├── data-pipeline/    # Yemeksepeti web scraper (Playwright)
├── ai-service/       # Öneri motoru (Python)
└── docs/             # SRS, tasarım ve kullanım kılavuzu
```

---

## 📡 API Referansı

Backend `http://localhost:3000` adresinde çalışır.

| Endpoint | Açıklama |
|----------|----------|
| `GET /api/health` | Sistem durumu ve yüklü veri özeti |
| `GET /api/cities` | Desteklenen şehirleri listele |
| `GET /api/districts?city=bursa` | Şehrin ilçelerini listele |
| `GET /api/geo-city` | Sunucu taraflı IP'den otomatik şehir/ilçe tespiti |
| `GET /api/deals?city=bursa` | En iyi fırsatları getir (sayfalı) |
| `GET /api/search?q=burger&city=bursa` | Ürün ara (sayfalı, skorlu) |
| `GET /api/compare?query=tavuk&city=bursa` | Platformlar arası fiyat karşılaştır |
| `GET /api/suspicious-discounts?city=bursa` | Şüpheli indirimler |
| `POST /api/auth/register` | Kayıt |
| `POST /api/auth/login` | Giriş |
| `GET /api/profile/:userId` | Profil getir |
| `PUT /api/profile/:userId` | Profil güncelle |

**Ortak query parametreleri:** `city`, `district`, `page`, `limit`, `sort` (`price_asc` / `price_desc` / `discount`), `minPrice`, `maxPrice`

---

## 🛠 Teknoloji Yığını

| Katman | Teknoloji |
|--------|-----------|
| Mobil | Flutter 3.22+ (iOS & Android) |
| Backend | Node.js 18+ + Express 5 |
| Veritabanı | PostgreSQL 14+ (opsiyonel — JSON fallback var) |
| Veri toplama | Python + Playwright (Yemeksepeti scraper) |
| Konum | ipapi.co + ipinfo.io + Geolocator + Geocoding |

---

## 👥 Ekip

| Alan | Üyeler |
|------|--------|
| **Frontend (Flutter)** | Fatma Nur Yazıcı, Mualla Gülsüm Çapar |
| **Backend (Node.js)** | Efekan Aksoy, Okan Aydınhan, Edem Makhsudov |
| **AI / Öneri** | Abdullah Çelik, Ahmet Yılmaz |
| **Veritabanı** | Fuat Üzülmez, Abdullah Çelik, Edem Makhsudov |

---

## 📋 Geliştirme Süreci

- **Metodoloji:** Agile / Scrum (2 haftalık sprintler)
- **Gereksinim:** IEEE 830 uyumlu SRS v1.0
- **Versiyon kontrolü:** Feature Branch + Pull Request
- **Test:** Unit, Integration, kullanım senaryoları

---

## 📚 Dokümanlar

- [Yazılım Gereksinim Dokümanı (SRS)](docs/NeYesem_SRS_v1_0.pdf)
- [Yazılım Tasarım Dokümanı](docs/NeYesem_Tasarim_Dokumani_v1.0.pdf)
- [Kullanım Kılavuzu](docs/NeYesem_Kullanim_Kilavuzu_v1.0.pdf)
- [Kurulum Rehberi](KURULUM.md)

---

## ⚠️ Önemli Notlar

- `backend/.env` dosyası gitignore'dadır — `.env.example`'ı kopyalayıp düzenleyin
- `backend/data/users.json` runtime'da otomatik oluşturulur
- Büyük veri dosyaları (`restaurants.original.json`, scraper çıktıları) gitignore'dadır
- Uygulama **sipariş almaz** — yalnızca karşılaştırma ve yönlendirme yapar

---

*NeYesem ile daha bilinçli ve ekonomik yemek kararları verin.*
