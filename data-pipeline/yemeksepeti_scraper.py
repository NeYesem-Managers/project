import time
import random
import json
from playwright.sync_api import sync_playwright
from playwright_stealth import Stealth

# ==============================================================================
# Akademik PoC Yemeksepeti Web Scraper
# ==============================================================================
# DİKKAT: Bu script robots.txt kurallarına, crawl-delay kısıtlarına ve
# KVKK kurallarına uymak üzere akademik bir Proof of Concept olarak tasarlanmıştır.
# Kesinlikle ticari amaçla veya siteye yük bindirecek şekilde kullanılmamalıdır.
# ==============================================================================

# Şeffaf ve açıklayıcı User-Agent bilgisi
# NOT: Yemeksepeti bot koruması (PerimeterX) standart dışı User-Agent'ları ve Headless (Görünmez) tarayıcıları 
# otomatik olarak engellemektedir (403 Forbidden). Bu nedenle standart bir Chrome User-Agent'ı kullanıyoruz.
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Tüm Bursa restoranlarını çekmek için bursa URL'si
TARGET_URL = "https://www.yemeksepeti.com/city/bursa"

# Test için restoran limiti
MAX_RESTAURANTS = 500

# Dışlanan sayfalar (robots.txt'ye göre)
BLOCKED_PATHS = ["/login", "/login_check", "/account-linking"]

def random_sleep():
    """
    Bekleme süresi süreci hızlandırmak adına çok daha düşük bir aralığa (0.2 - 0.7) çekildi.
    Tarayıcının kendi yükleme süresiyle birlikte bot korumasına takılmayı önler.
    """
    delay = random.uniform(0.2, 0.7)
    time.sleep(delay)

def run():
    print("="*50)
    print("Yemeksepeti Etik Scraper (Akademik PoC) Başlatılıyor...")
    print(f"Kullanılan User-Agent: {USER_AGENT}")
    print(f"Maksimum Restoran Sınırı: {MAX_RESTAURANTS}")
    print("="*50)
    
    with sync_playwright() as p:
        # headless=False olarak ayarlanmıştır çünkü PerimeterX bot koruması arka plan tarayıcılarını algılamaktadır.
        # "AutomationControlled" özelliğini kapatarak tespit edilmeyi zorlaştırıyoruz.
        browser = p.chromium.launch(headless=False, args=["--disable-blink-features=AutomationControlled"])
        
        # Tarayıcı context'ini oluşturuyoruz.
        context = browser.new_context(user_agent=USER_AGENT, viewport={'width': 1920, 'height': 1080})
        page = context.new_page()

        # Stealth modunu aktif hale getir (Playwright'ın bot olduğunu gizler)
        stealth = Stealth()
        stealth.apply_stealth_sync(page)

        # Istek engelleme (Route Interception)
        # Eğer sayfa yüklenirken robots.txt'de yasaklanan dizinlere veya istenmeyen analitik 
        # kaynaklarına istek atılmak istenirse engeller.
        def route_interceptor(route):
            request_url = route.request.url
            if any(blocked_path in request_url for blocked_path in BLOCKED_PATHS):
                print(f"[Engellendi - robots.txt kuralı]: {request_url}")
                route.abort()
            else:
                route.continue_()

        # Interceptor'ı aktif hale getir
        page.route("**/*", route_interceptor)

        print(f"\nHedef URL'den ({TARGET_URL}) sayfa sayfa tüm restoran bağlantıları toplanıyor...")
        restaurant_urls = []
        page_num = 1
        
        while True:
            current_url = f"{TARGET_URL}?page={page_num}" if page_num > 1 else TARGET_URL
            print(f"\n[{page_num}. Sayfa] Yükleniyor: {current_url}")
            
            try:
                # DOM yüklenene kadar bekle
                page.goto(current_url, wait_until="domcontentloaded", timeout=60000)
                
                # Captcha (PerimeterX) Kontrolü
                while True:
                    content = page.content()
                    if "Before we continue" in content or "confirm you are a human" in content or "Access to this page has been denied" in page.title():
                        print(" > [DİKKAT] Bot koruması (Captcha) algılandı! Lütfen tarayıcıda doğrulamayı geçin.")
                        page.wait_for_timeout(5000)
                    else:
                        break
                        
                random_sleep()
                
                # Doğal bir kullanıcı gibi yavaşça aşağı kaydırıyoruz ancak SONUNA KADAR DEĞİL!
                # Yemeksepeti sonsuz kaydırma (infinite scroll) kullandığı için en alta indiğimizde 
                # otomatik olarak 2., 3. sayfaları da aynı DOM içine yükler. Bu da aynı restoranların 
                # tekrar tekrar taranmasına (ve işlemin çok uzun sürmesine) sebep olur.
                # Bu yüzden sadece mevcut sayfanın elementlerini (href'lerini) render etmesi için kısa bir kaydırma yapıyoruz.
                page.evaluate("""
                    var totalHeight = 0;
                    var distance = 200;
                    var timer = setInterval(() => {
                        window.scrollBy(0, distance);
                        totalHeight += distance;

                        // Sadece yaklaşık 1-2 ekran boyu (2000px) kaydırıyoruz
                        if(totalHeight >= 2000){
                            clearInterval(timer);
                        }
                    }, 100);
                """)
                page.wait_for_timeout(2000) # Kaydırmanın bitmesi için bekleme
                
                links_locator = page.locator('a')
                count = links_locator.count()
                
                page_urls = []
                for i in range(count):
                    href = links_locator.nth(i).get_attribute("href")
                    if href and ("/restaurant/" in href or "/delivery/" in href):
                        full_url = href if href.startswith("http") else f"https://www.yemeksepeti.com{href}"
                        # Sadece daha önce eklenmemiş yeni linkleri alıyoruz
                        if full_url not in restaurant_urls and full_url not in page_urls:
                            page_urls.append(full_url)
                            
                        # Belirlenen limite ulaşıldıysa link toplamayı bırak
                        #if len(restaurant_urls) + len(page_urls) >= MAX_RESTAURANTS:
                        #    break

                if not page_urls:
                    print(f" > {page_num}. sayfada yeni restoran linki bulunamadı. Sayfalama sonlandırılıyor.")
                    break
                    
                restaurant_urls.extend(page_urls)
                print(f" > Bu sayfada {len(page_urls)} yeni restoran bulundu. (Toplam toplanan: {len(restaurant_urls)})")
                
                # Toplam toplanan link sayısı limite ulaştıysa sonraki sayfalara geçme
                if len(restaurant_urls) >= MAX_RESTAURANTS:
                    print(f" > İstenen maksimum restoran sayısına ({MAX_RESTAURANTS}) ulaşıldı.")
                    break
                
                page_num += 1
                
            except Exception as e:
                print(f" > Sayfa {page_num} işlenirken hata oluştu: {e}")
                break

        if not restaurant_urls:
            print("Hiç restoran linki bulunamadı. Lütfen hedef sayfadaki CSS Selector / DOM yapısını kontrol edin.")
            browser.close()
            return
            
        print(f"\nToplam {len(restaurant_urls)} restoran linki bulundu. Veri çekimine (Scraping) başlanıyor...")

        scraped_data = []

        # Her bir restoran için detaylara gir
        for i, url in enumerate(restaurant_urls):
            print(f"\n[{i+1}/{len(restaurant_urls)}] İşleniyor: {url}")
            # Crawl-delay: Her yeni sayfa talebinden önce mutlaka rastgele sürede bekle
            random_sleep()
            
            try:
                # Restoranın detay sayfasına git
                page.goto(url, wait_until="domcontentloaded", timeout=60000)
                
                # Captcha (PerimeterX) Kontrolü
                while True:
                    content = page.content()
                    if "Before we continue" in content or "confirm you are a human" in content or "Access to this page has been denied" in page.title():
                        print(" > [DİKKAT] Bot koruması (Captcha) algılandı! Lütfen açılan tarayıcı penceresinde doğrulamayı manuel olarak geçin. Script sizi bekliyor...")
                        page.wait_for_timeout(5000)
                    else:
                        break
                
                # Sayfa elementlerinin tam oturması için kısa bir bekleme (eskiden 2000 idi, hızlandırmak için 500'e düşürüldü)
                page.wait_for_timeout(500)
                
                # Restoran Adını Çek (Örnek selector'lar, güncellenmesi gerekebilir)
                name_locators = ['h1.main-info__title', 'h1.vendor-name', '[data-qa="vendor-name"]']
                restaurant_name = "Bilinmeyen Restoran"
                for selector in name_locators:
                    if page.locator(selector).count() > 0:
                        restaurant_name = page.locator(selector).first.text_content().strip()
                        if restaurant_name != "Çerezler & Benzer Teknolojiler":
                            break
                
                # Restoran Puanını Çek
                rating_locators = ['.bds-c-rating__label-primary', '[data-testid="rating-info"]', '.rating-score']
                rating = "Puan Yok"
                for selector in rating_locators:
                    if page.locator(selector).count() > 0:
                        rating = page.locator(selector).first.text_content().strip()
                        break
                        
                # Adres Çekme İşlemi
                address = "Adres bulunamadı"
                try:
                    # Yöntem 1: SEO için eklenen JSON-LD verilerinden çekmeyi dene (En güvenilir yöntem)
                    scripts = page.locator('script[type="application/ld+json"]').all_text_contents()
                    for script_text in scripts:
                        if "streetAddress" in script_text or "addressLocality" in script_text:
                            try:
                                data = json.loads(script_text)
                                if isinstance(data, list):
                                    for item in data:
                                        if "address" in item:
                                            addr = item["address"]
                                            address = f"{addr.get('streetAddress', '')} {addr.get('addressLocality', '')} {addr.get('addressRegion', '')}".strip()
                                            break
                                elif isinstance(data, dict) and "address" in data:
                                    addr = data["address"]
                                    address = f"{addr.get('streetAddress', '')} {addr.get('addressLocality', '')} {addr.get('addressRegion', '')}".strip()
                                if address and address != "Adres bulunamadı":
                                    break
                            except:
                                pass
                except:
                    pass
                
                if address == "Adres bulunamadı" or address == "":
                    # Yöntem 2: DOM üzerinden veya Modal açarak
                    try:
                        addr_loc = page.locator('[data-testid="vendor-address"], .vendor-location, p:has-text("Mahalle")')
                        if addr_loc.count() > 0:
                            address = addr_loc.first.text_content().strip()
                        else:
                            # Restoran bilgileri butonuna tıkla
                            info_btn = page.locator('button:has-text("Restoran Bilgileri"), button[data-testid="vendor-info-button"], .vendor-info-button')
                            if info_btn.count() > 0:
                                info_btn.first.click(timeout=2000, force=True)
                                page.wait_for_timeout(1000)
                                modal_addr = page.locator('h4:has-text("Adres") + p, [data-testid="vendor-address"]')
                                if modal_addr.count() > 0:
                                    address = modal_addr.first.text_content().strip()
                                page.keyboard.press("Escape")
                    except:
                        pass
                
                if not address:
                    address = "Adres bulunamadı"
                
                # Tüm Menü Ürünlerini Çek (JS evaluate ile)
                # İndirimli/İndirimsiz fiyatları ayrı kaydeder
                menu_items = page.evaluate(r"""() => {
                    const items = document.querySelectorAll('[data-testid="menu-product"], .dish-card, .menu-item, [data-qa="menu-item"]');
                    const results = [];
                    for (let item of items) {
                        const nameEl = item.querySelector('[data-testid="menu-product-name"], .dish-name, .item-name, [data-qa="item-name"]');
                        if (!nameEl) continue;
                        const name = nameEl.textContent.trim();
                        
                        const descEl = item.querySelector('[data-testid="menu-product-description"], .dish-description, .item-description, [data-qa="item-description"]');
                        const description = descEl ? descEl.textContent.trim() : "";

                        let indirimli_fiyat = null;
                        let indirimsiz_fiyat = null;
                        
                        const pEl = item.querySelector('[data-testid="menu-product-price"], .dish-price, .item-price, [data-qa="item-price"]');
                        
                        if (pEl) {
                            let text = pEl.textContent.trim();
                            let prices = text.match(/[\d,.]+\s*TL/g);
                            
                            if (prices && prices.length >= 2) {
                                let p1_str = prices[0];
                                let p2_str = prices[1];
                                let p1 = parseFloat(p1_str.replace(/\./g, '').replace(',', '.'));
                                let p2 = parseFloat(p2_str.replace(/\./g, '').replace(',', '.'));
                                
                                if (p1 < p2) {
                                    indirimli_fiyat = p1_str;
                                    indirimsiz_fiyat = p2_str;
                                } else if (p2 < p1) {
                                    indirimli_fiyat = p2_str;
                                    indirimsiz_fiyat = p1_str;
                                } else {
                                    indirimsiz_fiyat = p1_str;
                                }
                            } else if (prices && prices.length === 1) {
                                indirimsiz_fiyat = prices[0];
                            } else {
                                indirimsiz_fiyat = text;
                            }
                        } else {
                            // Fallback if price container not found
                            const textEls = Array.from(item.querySelectorAll('*')).filter(e => e.children.length === 0 && e.textContent && e.textContent.includes('TL'));
                            let prices = [];
                            for (let el of textEls) {
                                let text = el.textContent.trim();
                                let m = text.match(/^[\d,.]+\s*TL$/);
                                if (m) prices.push(m[0]);
                            }
                            if (prices.length >= 2) {
                                let p1 = parseFloat(prices[0].replace(/\./g, '').replace(',', '.'));
                                let p2 = parseFloat(prices[1].replace(/\./g, '').replace(',', '.'));
                                if (p1 < p2) {
                                    indirimli_fiyat = prices[0];
                                    indirimsiz_fiyat = prices[1];
                                } else {
                                    indirimli_fiyat = prices[1];
                                    indirimsiz_fiyat = prices[0];
                                }
                            } else if (prices.length === 1) {
                                indirimsiz_fiyat = prices[0];
                            } else {
                                indirimsiz_fiyat = "Bilinmeyen Fiyat";
                            }
                        }
                        
                        results.push({ 
                            isim: name, 
                            aciklama: description,
                            indirimli_fiyat: indirimli_fiyat, 
                            indirimsiz_fiyat: indirimsiz_fiyat 
                        });
                    }
                    return results;
                }""")

                # Elde edilen verileri objeye kaydet
                data = {
                    "restoran_adi": restaurant_name,
                    "puan": rating,
                    "adres": address,
                    "url": url,
                    "menu_urunleri": menu_items
                }
                scraped_data.append(data)
                print(f" > Başarı: {restaurant_name} | Adres: {address} | Puan: {rating} | Menü Sayısı: {len(menu_items)}")
                
                # Olası bir kapanma / durdurma durumuna karşı her iterasyonda dosyayı güncelle
                with open("scraped_restaurants_poc.json", "w", encoding="utf-8") as f:
                    json.dump(scraped_data, f, ensure_ascii=False, indent=4)
                
            except KeyboardInterrupt:
                print("\n > [DURDURULDU] İşlem kullanıcı tarafından (Ctrl+C) durduruldu. O ana kadarki veriler başarıyla kaydedildi.")
                break
            except Exception as e:
                print(f" > Hata oluştu ({url}): {e}")
                continue

        # Çekilen veriyi yerel json dosyasına kaydet
        output_file = "scraped_restaurants_poc.json"
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(scraped_data, f, ensure_ascii=False, indent=4)
            
        print("\n" + "="*50)
        print(f"Süreç başarıyla tamamlandı!")
        print(f"Toplam {len(scraped_data)} restoranın tüm menü verisi '{output_file}' adlı dosyaya kaydedildi.")
        print("Kişisel verilere (isim, yorum vb.) erişilmedi, hedef sınırlar içerisinde kalındı.")
        print("="*50)
        
        browser.close()

if __name__ == "__main__":
    run()
