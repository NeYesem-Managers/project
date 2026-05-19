# Yemeksepeti Web Scraper (Akademik PoC)

Bu proje, akademik bir Proof of Concept (PoC) çalışması kapsamında Yemeksepeti (Bursa bölgesi) üzerindeki restoran ve menü verilerini etik web scraping kurallarına uygun olarak çekmek amacıyla geliştirilmiştir. Siteye yük bindirmemek ve robots.txt kurallarına, bot kısıtlamalarına uymak için özel olarak yapılandırılmıştır.

## 🛠️ Teknolojiler
- **Python 3**
- **Playwright** (Dinamik sayfaları yüklemek ve DOM üzerinden veri çekmek için)
- **Playwright-Stealth** (PerimeterX gibi bot koruma sistemlerini aşmak ve tarayıcıyı gerçek bir kullanıcı gibi göstermek için)

## 📂 Proje Dosyaları ve İşlevleri

### 1. Ana Script
* **`yemeksepeti_scraper.py`**
  Projenin ana veri çekme (scraping) betiğidir. Bursa (`/city/bursa`) sayfasını ziyaret ederek sayfalama üzerinden restoran linklerini toplar. Ardından her restorana girerek şu bilgileri ayıklar:
  - Restoran Adı
  - Restoran Puanı
  - Adres Bilgisi (SEO JSON-LD verilerinden veya DOM modal'larından)
  - Menü Ürünleri (Adı, açıklaması, eğer indirim varsa "indirimli" ve "indirimsiz" fiyatları ayrı olarak)
  Elde edilen verileri işlem sırasında kaybolmasını önlemek amacıyla periyodik olarak `scraped_restaurants_poc.json` dosyasına kaydeder. Sistem herhangi bir "Captcha" bot engellemesi fark ederse duraklayarak manuel doğrulama bekler.

### 2. Geliştirme, Test ve Debug Dosyaları
Geliştirme aşamasında CSS/DOM yapılarını incelemek ve karmaşık veri tiplerini çözmek için kullanılan geçici dosyalardır:
* **`get_menu_description.py`**: Menü ürün açıklamalarının sitedeki HTML dom elementleri içerisinde nerede yer aldığını tespit etmek ve test etmek için yazılmış deneme scripti.
* **`scratch_fetch.py` & `scratch_fetch2.py`**: İndirimli menü ürünlerindeki "orijinal fiyat" ve "indirimli fiyat" ayrımlarını, eski fiyatın üstü çizili (line-through) olup olmamasını regex ve Playwright yardımıyla test edip çözümleyen deneme betikleri.
* **`debug2.py`**: Sayfa üzerinde restoranın sahip olduğu `/5` formatındaki değerlendirme puanını çekmek için Stealth modülünü ve DOM içi aramayı test eden debug scripti.

### 3. Veri ve Log Dosyaları
* **`scraped_restaurants_poc.json`**: Ana scraper'ın verileri dışarıya aktardığı nihai JSON veri setidir.
* **`debug_ys.html`, `discount_item.html`, `item_html.txt`, `sample_item.html`**: Geliştirme aşamasında analiz yapmak için scriptler tarafından kaydedilmiş geçici site kaynak kodlarıdır.

## ⚠️ Uyarılar ve Kullanım Koşulları
- **Akademik Kullanım:** Bu proje yalnızca eğitim/akademik amaçlarla yazılmıştır; ticari maksatla kullanılamaz.
- **Bot Koruması:** Yemeksepeti ciddi bir "PerimeterX" bot kalkanı kullandığı için script tamamen görünmez (headless=True) modda çalışmamaktadır. İstekler normal kullanıcı sınırlarına çekilmiştir (random bekleme süreleri dahil).
- **KVKK Uyumluluğu:** Uygulama, sadece herkese açık işletme profillerindeki ürünleri ve fiyatları alır; son kullanıcıların kişisel verileriyle ilgilenmez.
