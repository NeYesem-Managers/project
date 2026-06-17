# NeYesem — Kurulum ve Çalıştırma Rehberi

Bu rehber, projeyi **kendi bilgisayarında sıfırdan** çalıştırmak için gereken
tüm adımları içerir. Mimari: **Python (veri) + PostgreSQL + Node/Express (backend)
+ Flutter (mobil/web)**.

> Komut örnekleri **Windows PowerShell** içindir. macOS/Linux kullanıyorsan
> ortam değişkeni satırlarını kendi kabuğuna göre uyarla (`export VAR=...`).

---

## 1. Gereksinimler (bir kez kurulur)

| Araç | Önerilen sürüm | İndirme |
|------|----------------|---------|
| **Node.js** (npm ile) | 18+ | https://nodejs.org |
| **PostgreSQL** | 14+ (projede 18 kullanıldı) | https://www.postgresql.org/download |
| **Python** | 3.10+ (projede 3.13) | https://www.python.org |
| **Flutter SDK** | 3.22+ (projede 3.44) | https://docs.flutter.dev/get-started/install |

Kurulum sonrası şu komutların çalıştığını doğrula (gerekirse araçları PATH'e ekle
ve **terminali yeniden aç**):

```powershell
node -v
npm -v
psql --version
python --version
flutter --version
```

> **Flutter PATH:** Kurduktan sonra `flutter` tanınmıyorsa, Flutter'ın `bin`
> klasörünü (`...\flutter\bin`) Kullanıcı PATH'ine ekleyip yeni bir terminal aç.

---

## 2. Projeyi al

```powershell
git clone <REPO_URL> neyesem
cd neyesem
```

> ZIP olarak aldıysan klasörü aç ve içine gir. `node_modules`, `.env` ve
> `build/` klasörleri repoda **yer almaz** (herkes kendi kurar — aşağıdaki
> adımlar bunu hallediyor).

---

## 3. Veritabanını hazırla (PostgreSQL)

PostgreSQL kurulumunda belirlediğin **postgres şifresini** kullanacaksın.

```powershell
# Veritabanını oluştur (zaten varsa "already exists" der, sorun değil)
createdb -U postgres ne_yesem

# Tabloları oluştur
psql -U postgres -d ne_yesem -f database/schema.sql
```

Her iki komut da postgres şifreni soracaktır.

> **Tablo açmana gerek yok** — `schema.sql` tüm tabloları (platformlar, sehirler,
> restoranlar, kategoriler, urunler) kurar. Platformlar (Yemeksepeti/Getir) veri
> yüklenirken otomatik eklenir.

---

## 4. Örnek veriyi veritabanına yükle

Python bağımlılıklarını kur:

```powershell
cd database
pip install -r requirements.txt
cd ..
```

Veritabanı bağlantısı için ortam değişkenlerini ver ve içe aktar
(**`<SIFRE>`** yerine kendi postgres şifreni yaz):

```powershell
$env:DB_PASSWORD="<SIFRE>"
$env:DB_NAME="ne_yesem"
$env:DB_USER="postgres"
$env:PYTHONIOENCODING="utf-8"     # Windows konsolunda Türkçe karakter hatasını önler

cd database

# Yemeksepeti verisi (sınıflandırılmış JSON repoda hazır)
python json_to_db.py --yemeksepeti ../backend/data/restaurants.json --sehir bursa

# Getir verisi (repoda hazır — istediğin şehri yükleyebilirsin: bursa/ankara/istanbul/izmir)
python json_to_db.py --folder ../backend/data/getir_output/output/bursa/getir_yemek --sehir bursa

# Kontrol
python json_to_db.py --istatistik
cd ..
```

Beklenen: ~392 Yemeksepeti + ~582 Getir restoranı, on binlerce ürün.

---

## 5. Backend'i çalıştır (Node/Express)

```powershell
cd backend
npm install
```

`backend/.env` dosyasını oluştur (örnek için `backend/.env.example` var).
**`<SIFRE>`** yerine kendi postgres şifreni yaz:

```dotenv
PORT=3000
USE_DB=true
DB_HOST=localhost
DB_PORT=5432
DB_NAME=ne_yesem
DB_USER=postgres
DB_PASSWORD=<SIFRE>
```

> `USE_DB=true` → PostgreSQL'den okur. `false` yaparsan DB olmadan
> `backend/data/` içindeki JSON dosyalarından okur (DB kurmadan hızlı deneme).

Başlat:

```powershell
npm start
```

`NeYesem demo backend çalışıyor: http://localhost:3000` ve
`[DB] ... ürün, ... restoran belleğe alındı.` satırlarını görmelisin.

Hızlı test (yeni bir terminalde):

```powershell
curl "http://localhost:3000/api/products?type=yemek&limit=3"
curl "http://localhost:3000/api/products?type=sos&limit=3"
curl "http://localhost:3000/api/compare?query=tantuni"
```

---

## 6. Mobil/web uygulamayı çalıştır (Flutter)

Backend açıkken, **yeni bir terminalde**:

```powershell
cd mobile
flutter pub get
flutter run -d chrome      # en kolayı; veya: flutter run -d windows / -d <cihaz>
```

Açılınca: giriş ekranı (demo bilgileri dolu) → **Giriş yap** → Ana Sayfa'da
**Yemekler / Soslar / İçecekler / Ekstralar** filtre çipleri ve ürün listeleri.

> **Cihaz listesi:** `flutter devices`. Chrome/Edge web için ekstra kurulum
> gerekmez. Windows masaüstü (`-d windows`) için Geliştirici Modu gerekebilir.

### Backend farklı bir adreste mi?
Uygulama varsayılan olarak `http://localhost:3000/api` adresine bağlanır.
Farklı bir host için:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.50:3000/api
```

---

## 7. (Opsiyonel) Yeni veri çekme — Yemeksepeti scraper

Hazır veri repoda mevcut; **taze veri** çekmek istersen:

```powershell
cd data-pipeline
pip install -r requirements.txt
python -m playwright install chromium   # ilk sefer tarayıcıyı indirir

# Görünür tarayıcı (captcha'yı manuel geçmek için) — önerilen ilk kullanım
python yemeksepeti_scraper.py --no-headless --city bursa
```

Çıktı: `scraped_restaurants_poc_classified.json` (her ürün `urun_tipi` ile
etiketli). Sonra DB'ye yükle:

```powershell
cd ../database
$env:DB_PASSWORD="<SIFRE>"; $env:PYTHONIOENCODING="utf-8"
python json_to_db.py --yemeksepeti ../data-pipeline/scraped_restaurants_poc_classified.json --sehir bursa
```

> Diğer scraper seçenekleri: `python yemeksepeti_scraper.py --help`

---

## Sık karşılaşılan sorunlar

| Sorun | Çözüm |
|-------|-------|
| `flutter` / `psql` / `python` tanınmıyor | Aracı PATH'e ekle ve **terminali yeniden aç**. |
| `Veritabanına bağlanılamadı` | `.env` / ortam değişkenlerindeki `DB_PASSWORD` doğru mu? PostgreSQL servisi çalışıyor mu? |
| Konsolda `UnicodeEncodeError` (Türkçe karakter) | `$env:PYTHONIOENCODING="utf-8"` ayarla. |
| Flutter'da **beyaz ekran** (web) | `flutter run -d chrome --no-web-resources-cdn` ile dene; ya da sayfayı yenile. |
| Backend `[DB] ...` satırı yok / ürün gelmiyor | `.env`'de `USE_DB=true` mi? Adım 4'teki veri yüklemesini yaptın mı? |
| pgAdmin'de tablolar boş görünüyor | Veritabanına/Tables'a **sağ tık → Refresh**. |

---

## Özet (kısa yol)

```powershell
# 1) DB
createdb -U postgres ne_yesem
psql -U postgres -d ne_yesem -f database/schema.sql

# 2) Veri
cd database; pip install -r requirements.txt
$env:DB_PASSWORD="<SIFRE>"; $env:DB_NAME="ne_yesem"; $env:DB_USER="postgres"; $env:PYTHONIOENCODING="utf-8"
python json_to_db.py --yemeksepeti ../backend/data/restaurants.json --sehir bursa
python json_to_db.py --folder ../backend/data/getir_output/output/bursa/getir_yemek --sehir bursa
cd ..

# 3) Backend (.env oluştur: USE_DB=true + DB_PASSWORD)
cd backend; npm install; npm start
# (yeni terminal)

# 4) Uygulama
cd mobile; flutter pub get; flutter run -d chrome
```
