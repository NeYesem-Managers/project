"""
Ne Yesem - JSON to PostgreSQL Importer
=======================================
Bu script, scraper'ların ürettiği JSON dosyalarını okuyup
PostgreSQL veritabanına otomatik olarak kaydeder.

Kullanım:
    python json_to_db.py --folder output/bursa/getir_yemek
    python json_to_db.py --folder output/bursa/getir_yemek --sehir bursa
"""

import json
import os
import sys
import argparse
import psycopg2
from psycopg2 import sql
from datetime import datetime
from dotenv import load_dotenv

# Scraper ile aynı sınıflandırıcıyı kullan (data-pipeline klasöründen)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "data-pipeline"))
from product_classifier import classify_product


def _parse_price(value):
    """
    Türkçe fiyat metnini float'a çevirir. Nokta=binlik, virgül=ondalık.
      '89,17 TL'    -> 89.17     (virgül ondalık)
      '1.574,12 TL' -> 1574.12   (nokta binlik, virgül ondalık)
      '1.420 TL'    -> 1420.0    (nokta binlik, ondalık yok)  <-- ÖNEMLİ
      '104.90'      -> 104.90    (nokta ondalık, 2 hane)
      '800 TL'      -> 800.0
      None / boş    -> None
    """
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if not text:
        return None
    text = text.replace("₺", "").replace("TL", "").replace("tl", "").replace(" ", "").strip()
    if not text:
        return None

    if "," in text:
        # Virgül ondalık ayraç; noktalar binlik ayraçtır.
        text = text.replace(".", "").replace(",", ".")
    elif "." in text:
        # Sadece nokta var: son noktadan sonra TAM 2 hane varsa ondalık,
        # aksi halde (3 hane ya da çoklu nokta) binlik ayraç kabul edilir.
        son = text.rsplit(".", 1)[1]
        if len(son) == 2:
            text = text.rsplit(".", 1)[0].replace(".", "") + "." + son
        else:
            text = text.replace(".", "")
    try:
        return round(float(text), 2)
    except ValueError:
        return None

# .env dosyasından ayarları yükle
load_dotenv()

# =============================================
# VERİTABANI BAĞLANTI AYARLARI
# .env dosyasından okunur, koda şifre yazılmaz!
# =============================================
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "dbname": os.getenv("DB_NAME", "ne_yesem"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "")
}


def veritabanina_baglan():
    """PostgreSQL veritabanına bağlanır."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        conn.autocommit = False  # Transaction kullanacağız
        print("[OK] Veritabanına bağlanıldı.")
        return conn
    except Exception as e:
        print(f"[HATA] Veritabanına bağlanılamadı: {e}")
        sys.exit(1)


def platform_ekle(cursor, platform_adi):
    """
    Platform tablosuna yeni platform ekler.
    Zaten varsa mevcut ID'yi döndürür.
    
    CONFLICT = Çakışma demek. Aynı isimde platform varsa
    hata vermek yerine mevcut kaydın ID'sini döndürür.
    """
    cursor.execute("""
        INSERT INTO platformlar (ad)
        VALUES (%s)
        ON CONFLICT (ad) DO NOTHING;
    """, (platform_adi,))
    
    cursor.execute("SELECT id FROM platformlar WHERE ad = %s;", (platform_adi,))
    return cursor.fetchone()[0]


def sehir_ekle(cursor, sehir_adi):
    """
    Şehir tablosuna yeni şehir ekler.
    Zaten varsa mevcut ID'yi döndürür.
    """
    # Şehir adının ilk harfini büyük yap
    sehir_adi = sehir_adi.strip().title()
    
    cursor.execute("""
        INSERT INTO sehirler (ad)
        VALUES (%s)
        ON CONFLICT (ad) DO NOTHING;
    """, (sehir_adi,))
    
    cursor.execute("SELECT id FROM sehirler WHERE ad = %s;", (sehir_adi,))
    return cursor.fetchone()[0]


def restoran_ekle(cursor, data, sehir_id, platform_id):
    """
    Restoran bilgilerini veritabanına ekler.
    Aynı kaynak_id + platform_id varsa günceller (UPSERT).
    
    UPSERT = UPDATE + INSERT demek.
    Kayıt yoksa ekler, varsa günceller.
    """
    kaynak_id = data.get("id", "")
    
    cursor.execute("""
        INSERT INTO restoranlar 
            (kaynak_id, ad, slug, sehir_id, platform_id, puan, puan_sayisi,
             min_siparis, teslimat_ucreti, teslimat_sure_min, teslimat_sure_max, acik_mi)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (kaynak_id, platform_id) 
        DO UPDATE SET
            ad = EXCLUDED.ad,
            puan = EXCLUDED.puan,
            puan_sayisi = EXCLUDED.puan_sayisi,
            min_siparis = EXCLUDED.min_siparis,
            teslimat_ucreti = EXCLUDED.teslimat_ucreti,
            teslimat_sure_min = EXCLUDED.teslimat_sure_min,
            teslimat_sure_max = EXCLUDED.teslimat_sure_max,
            acik_mi = EXCLUDED.acik_mi
        RETURNING id;
    """, (
        kaynak_id,
        data.get("name", "Bilinmiyor"),
        data.get("slug", ""),
        sehir_id,
        platform_id,
        data.get("rating"),
        data.get("rating_count"),
        data.get("min_order_amount"),
        data.get("delivery_fee"),
        data.get("delivery_time_min"),
        data.get("delivery_time_max"),
        data.get("is_open", True)
    ))
    
    return cursor.fetchone()[0]


def menu_ekle(cursor, data, restoran_id):
    """
    Restoranın menüsünü (kategoriler + ürünler) veritabanına ekler.
    Önce eski menüyü siler, sonra yenisini ekler (temiz güncelleme).
    """
    # Önce bu restoranın eski ürünlerini ve kategorilerini sil
    cursor.execute("DELETE FROM urunler WHERE restoran_id = %s;", (restoran_id,))
    cursor.execute("DELETE FROM kategoriler WHERE restoran_id = %s;", (restoran_id,))
    
    menu = data.get("menu", {})
    categories = menu.get("categories", [])
    
    urun_sayisi = 0
    
    for kategori in categories:
        # Kategori ekle
        cursor.execute("""
            INSERT INTO kategoriler (kaynak_id, ad, restoran_id)
            VALUES (%s, %s, %s)
            RETURNING id;
        """, (
            kategori.get("id", ""),
            kategori.get("name", "Diğer"),
            restoran_id
        ))
        kategori_id = cursor.fetchone()[0]
        
        # Kategorideki ürünleri ekle
        kategori_adi = kategori.get("name", "Diğer")
        items = kategori.get("items", [])
        for item in items:
            urun_tipi = classify_product(
                isim=item.get("name", ""),
                kategori=kategori_adi,
                aciklama=item.get("description", "") or "",
            )
            cursor.execute("""
                INSERT INTO urunler 
                    (kaynak_id, ad, aciklama, kategori_id, restoran_id,
                     fiyat, orijinal_fiyat, indirim_yuzdesi, urun_tipi, gorsel_url, musait_mi)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (
                item.get("id", ""),
                item.get("name", "Bilinmiyor"),
                item.get("description"),
                kategori_id,
                restoran_id,
                item.get("price", 0),
                item.get("original_price"),
                item.get("discount_percentage"),
                urun_tipi,
                item.get("image_url", ""),
                item.get("is_available", True)
            ))
            urun_sayisi += 1
    
    return urun_sayisi


def json_dosyasi_isle(cursor, dosya_yolu, sehir_id, platform_id):
    """Tek bir JSON dosyasını okuyup veritabanına kaydeder."""
    try:
        with open(dosya_yolu, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        # Restoran ekle
        restoran_id = restoran_ekle(cursor, data, sehir_id, platform_id)
        restoran_adi = data.get("name", "Bilinmiyor")
        
        # Menüyü ekle
        urun_sayisi = menu_ekle(cursor, data, restoran_id)
        
        print(f"  [+] {restoran_adi} — {urun_sayisi} ürün eklendi")
        return True
        
    except json.JSONDecodeError:
        print(f"  [!] {dosya_yolu} — Geçersiz JSON, atlanıyor")
        return False
    except Exception as e:
        print(f"  [!] {dosya_yolu} — Hata: {e}")
        return False


def klasor_isle(folder_path, sehir_adi=None):
    """
    Bir klasördeki tüm JSON dosyalarını işler.
    
    Klasör yapısı: output/bursa/getir_yemek/restoran.json
    Eğer sehir_adi verilmezse klasör yolundan tahmin eder.
    """
    # Klasör var mı kontrol et
    if not os.path.isdir(folder_path):
        print(f"[HATA] Klasör bulunamadı: {folder_path}")
        sys.exit(1)
    
    # JSON dosyalarını bul
    json_dosyalari = [f for f in os.listdir(folder_path) if f.endswith(".json")]
    
    if not json_dosyalari:
        print(f"[HATA] Klasörde JSON dosyası bulunamadı: {folder_path}")
        sys.exit(1)
    
    print(f"\n{'='*50}")
    print(f"  Ne Yesem — JSON → Veritabanı Aktarımı")
    print(f"{'='*50}")
    print(f"  Klasör  : {folder_path}")
    print(f"  Dosya   : {len(json_dosyalari)} JSON")
    
    # Şehir adını belirle
    if not sehir_adi:
        # Klasör yolundan tahmin et: output/bursa/getir_yemek
        parts = folder_path.replace("\\", "/").split("/")
        if len(parts) >= 2:
            sehir_adi = parts[-2]  # "bursa"
        else:
            sehir_adi = "Bilinmiyor"
    
    # Platform adını belirle (klasör adından)
    parts = folder_path.replace("\\", "/").split("/")
    platform_adi = parts[-1] if parts else "bilinmiyor"  # "getir_yemek"
    
    # Platform adını güzelleştir
    platform_map = {
        "getir_yemek": "Getir Yemek",
        "trendyol_go": "Trendyol Go",
        "yemeksepeti": "Yemeksepeti",
    }
    platform_adi = platform_map.get(platform_adi, platform_adi)
    
    print(f"  Şehir   : {sehir_adi.title()}")
    print(f"  Platform: {platform_adi}")
    print(f"{'='*50}\n")
    
    # Veritabanına bağlan
    conn = veritabanina_baglan()
    cursor = conn.cursor()
    
    try:
        # Platform ve şehir ekle
        platform_id = platform_ekle(cursor, platform_adi)
        sehir_id = sehir_ekle(cursor, sehir_adi)
        
        # Her JSON dosyasını işle
        basarili = 0
        hatali = 0
        
        for dosya in sorted(json_dosyalari):
            dosya_yolu = os.path.join(folder_path, dosya)
            if json_dosyasi_isle(cursor, dosya_yolu, sehir_id, platform_id):
                basarili += 1
            else:
                hatali += 1
        
        # Her şey başarılıysa kaydet (COMMIT)
        conn.commit()
        
        print(f"\n{'='*50}")
        print(f"  SONUÇ")
        print(f"{'='*50}")
        print(f"  Başarılı : {basarili} restoran")
        print(f"  Hatalı   : {hatali} dosya")
        print(f"  Toplam   : {basarili + hatali} dosya işlendi")
        print(f"{'='*50}\n")
        
    except Exception as e:
        # Hata olursa geri al (ROLLBACK)
        conn.rollback()
        print(f"\n[HATA] İşlem geri alındı: {e}")
    
    finally:
        cursor.close()
        conn.close()
        print("[OK] Veritabanı bağlantısı kapatıldı.")


def yemeksepeti_dosyasi_isle(dosya_yolu, sehir_adi="bursa", platform_adi="Yemeksepeti"):
    """
    Yemeksepeti/Trendyol scraper'ının ürettiği TEK BÜYÜK JSON dosyasını işler.
    Format: [ {restoran_adi, puan, adres, url, menu_urunleri:[{isim, kategori,
            aciklama, indirimli_fiyat, indirimsiz_fiyat, urun_tipi}]} , ... ]

    platform_adi: Kayıtların hangi platforma ait olduğunu belirler
    ("Yemeksepeti" veya "Trendyol Yemek"). Format aynı olduğu için tek importer
    her iki kaynağı da yükleyebilir.
    """
    if not os.path.isfile(dosya_yolu):
        print(f"[HATA] Dosya bulunamadı: {dosya_yolu}")
        sys.exit(1)

    with open(dosya_yolu, "r", encoding="utf-8") as f:
        restoranlar = json.load(f)

    print(f"\n{'='*50}")
    print(f"  Ne Yesem — {platform_adi} JSON → Veritabanı")
    print(f"{'='*50}")
    print(f"  Dosya    : {dosya_yolu}")
    print(f"  Restoran : {len(restoranlar)}")
    print(f"  Şehir    : {sehir_adi.title()}")
    print(f"  Platform : {platform_adi}")
    print(f"{'='*50}\n")

    conn = veritabanina_baglan()
    cursor = conn.cursor()
    try:
        platform_id = platform_ekle(cursor, platform_adi)
        sehir_id = sehir_ekle(cursor, sehir_adi)

        basarili = 0
        toplam_urun = 0
        for idx, rest in enumerate(restoranlar):
            ad = rest.get("restoran_adi", "Bilinmeyen Restoran")
            if ad in ("Bilinmeyen Restoran", "Çerezler & Benzer Teknolojiler"):
                continue
            # puan "4,6" veya "4.6" olabilir
            puan_raw = str(rest.get("puan", "")).replace(",", ".")
            try:
                puan = float(puan_raw)
            except ValueError:
                puan = None

            kaynak_id = rest.get("url", f"ys-{idx}")
            cursor.execute("""
                INSERT INTO restoranlar (kaynak_id, ad, slug, sehir_id, platform_id, puan, acik_mi)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (kaynak_id, platform_id) DO UPDATE SET
                    ad = EXCLUDED.ad, puan = EXCLUDED.puan
                RETURNING id;
            """, (kaynak_id, ad, rest.get("url", ""), sehir_id, platform_id, puan, True))
            restoran_id = cursor.fetchone()[0]

            cursor.execute("DELETE FROM urunler WHERE restoran_id = %s;", (restoran_id,))
            cursor.execute("DELETE FROM kategoriler WHERE restoran_id = %s;", (restoran_id,))

            # Kategori adına göre kategori kayıtlarını grupla (cache)
            kategori_cache = {}
            urun_sayisi = 0
            for item in rest.get("menu_urunleri", []):
                kat_adi = item.get("kategori") or "Genel"
                if kat_adi not in kategori_cache:
                    cursor.execute("""
                        INSERT INTO kategoriler (ad, restoran_id) VALUES (%s, %s) RETURNING id;
                    """, (kat_adi, restoran_id))
                    kategori_cache[kat_adi] = cursor.fetchone()[0]
                kategori_id = kategori_cache[kat_adi]

                fiyat = _parse_price(item.get("indirimsiz_fiyat")) or _parse_price(item.get("indirimli_fiyat")) or 0
                indirimli = _parse_price(item.get("indirimli_fiyat"))
                orijinal = _parse_price(item.get("indirimsiz_fiyat"))
                # Güncel fiyat indirimliyse onu kullan
                guncel = indirimli if indirimli else (orijinal or fiyat)
                indirim_yuzdesi = None
                if indirimli and orijinal and orijinal > 0 and indirimli < orijinal:
                    indirim_yuzdesi = round((orijinal - indirimli) / orijinal * 100, 2)

                # urun_tipi: dosyada varsa kullan, yoksa hesapla
                urun_tipi = item.get("urun_tipi") or classify_product(
                    isim=item.get("isim", ""), kategori=kat_adi, aciklama=item.get("aciklama", "") or "")

                cursor.execute("""
                    INSERT INTO urunler (ad, aciklama, kategori_id, restoran_id,
                        fiyat, orijinal_fiyat, indirim_yuzdesi, urun_tipi, musait_mi)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);
                """, (
                    item.get("isim", "Bilinmiyor"),
                    item.get("aciklama"),
                    kategori_id,
                    restoran_id,
                    guncel,
                    orijinal if (indirimli and orijinal and indirimli < orijinal) else None,
                    indirim_yuzdesi,
                    urun_tipi,
                    True,
                ))
                urun_sayisi += 1
                toplam_urun += 1

            basarili += 1
            if basarili % 50 == 0:
                print(f"  [+] {basarili} restoran işlendi...")

        conn.commit()
        print(f"\n  SONUÇ: {basarili} restoran, {toplam_urun} ürün eklendi.\n")
    except Exception as e:
        conn.rollback()
        print(f"\n[HATA] İşlem geri alındı: {e}")
    finally:
        cursor.close()
        conn.close()
        print("[OK] Veritabanı bağlantısı kapatıldı.")


def istatistik_goster():
    """Veritabanındaki mevcut kayıt sayılarını gösterir."""
    conn = veritabanina_baglan()
    cursor = conn.cursor()
    
    tablolar = ["platformlar", "sehirler", "restoranlar", "kategoriler", "urunler"]
    
    print(f"\n{'='*40}")
    print(f"  Veritabanı İstatistikleri")
    print(f"{'='*40}")
    
    for tablo in tablolar:
        cursor.execute(f"SELECT COUNT(*) FROM {tablo};")
        sayi = cursor.fetchone()[0]
        print(f"  {tablo:15s} : {sayi} kayıt")
    
    print(f"{'='*40}\n")
    
    cursor.close()
    conn.close()


# =============================================
# ANA PROGRAM
# =============================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Ne Yesem — JSON dosyalarını veritabanına aktar"
    )
    parser.add_argument(
        "--folder", "-f",
        help="JSON dosyalarının bulunduğu klasör (örn: output/bursa/getir_yemek)",
        required=False
    )
    parser.add_argument(
        "--sehir", "-s",
        help="Şehir adı (belirtilmezse klasör yolundan tahmin edilir)",
        required=False
    )
    parser.add_argument(
        "--yemeksepeti", "-y",
        help="Yemeksepeti tek-dosya JSON yolu (örn: scraped_restaurants_poc_classified.json)",
        required=False
    )
    parser.add_argument(
        "--istatistik", "-i",
        action="store_true",
        help="Veritabanı istatistiklerini göster"
    )

    args = parser.parse_args()

    if args.istatistik:
        istatistik_goster()
    elif args.yemeksepeti:
        yemeksepeti_dosyasi_isle(args.yemeksepeti, args.sehir or "bursa", "Yemeksepeti")
    elif args.folder:
        klasor_isle(args.folder, args.sehir)
    else:
        print("Kullanım:")
        print("  python json_to_db.py --folder output/bursa/getir_yemek")
        print("  python json_to_db.py --yemeksepeti scraped_restaurants_poc_classified.json --sehir bursa")
        print("  python json_to_db.py --istatistik")
