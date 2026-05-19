-- =============================================
-- Ne Yesem — Veritabanı Şeması
-- =============================================
-- Bu dosya projenin PostgreSQL tablo yapısını oluşturur.
-- 
-- Kullanım:
--   1. PostgreSQL'de "ne_yesem" adında bir veritabanı oluşturun
--   2. Bu dosyayı pgAdmin Query Tool veya psql ile çalıştırın
--
-- psql ile:
--   psql -U postgres -d ne_yesem -f schema.sql
-- =============================================

-- Eski tabloları sil (varsa)
DROP TABLE IF EXISTS urunler CASCADE;
DROP TABLE IF EXISTS kategoriler CASCADE;
DROP TABLE IF EXISTS restoranlar CASCADE;
DROP TABLE IF EXISTS sehirler CASCADE;
DROP TABLE IF EXISTS platformlar CASCADE;

-- 1. Platformlar (Getir Yemek, Trendyol Go, Yemeksepeti...)
CREATE TABLE platformlar (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(100) NOT NULL UNIQUE,
    website VARCHAR(255),
    olusturma_tarihi TIMESTAMP DEFAULT NOW()
);

-- 2. Şehirler
CREATE TABLE sehirler (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(100) NOT NULL UNIQUE
);

-- 3. Restoranlar
CREATE TABLE restoranlar (
    id SERIAL PRIMARY KEY,
    kaynak_id VARCHAR(100),           -- Platformdaki orijinal ID
    ad VARCHAR(255) NOT NULL,
    slug VARCHAR(500),
    sehir_id INTEGER REFERENCES sehirler(id),
    platform_id INTEGER REFERENCES platformlar(id),
    puan DECIMAL(3,1),                -- Restoran puanı (ör: 4.6)
    puan_sayisi INTEGER,              -- Değerlendirme sayısı
    min_siparis DECIMAL(10,2),        -- Minimum sipariş tutarı
    teslimat_ucreti DECIMAL(10,2),    -- Teslimat ücreti
    teslimat_sure_min INTEGER,        -- Minimum teslimat süresi (dk)
    teslimat_sure_max INTEGER,        -- Maksimum teslimat süresi (dk)
    acik_mi BOOLEAN DEFAULT true,
    olusturma_tarihi TIMESTAMP DEFAULT NOW(),
    UNIQUE(kaynak_id, platform_id)    -- Aynı restoran aynı platformda tekrar eklenmesin
);

-- 4. Kategoriler (menü kategorileri)
CREATE TABLE kategoriler (
    id SERIAL PRIMARY KEY,
    kaynak_id VARCHAR(100),
    ad VARCHAR(255) NOT NULL,
    restoran_id INTEGER REFERENCES restoranlar(id) ON DELETE CASCADE
);

-- 5. Ürünler (menüdeki her yemek/içecek)
CREATE TABLE urunler (
    id SERIAL PRIMARY KEY,
    kaynak_id VARCHAR(100),           -- Platformdaki orijinal ürün ID
    ad VARCHAR(255) NOT NULL,
    aciklama TEXT,
    kategori_id INTEGER REFERENCES kategoriler(id) ON DELETE CASCADE,
    restoran_id INTEGER REFERENCES restoranlar(id) ON DELETE CASCADE,
    fiyat DECIMAL(10,2) NOT NULL,     -- Güncel fiyat
    orijinal_fiyat DECIMAL(10,2),     -- İndirim öncesi fiyat
    indirim_yuzdesi DECIMAL(5,2),     -- İndirim yüzdesi
    gorsel_url TEXT,
    musait_mi BOOLEAN DEFAULT true,
    tarih TIMESTAMP DEFAULT NOW()     -- Fiyatın kaydedildiği tarih
);

-- =============================================
-- INDEX'ler (sorguları hızlandırır)
-- =============================================
CREATE INDEX idx_restoranlar_sehir ON restoranlar(sehir_id);
CREATE INDEX idx_restoranlar_platform ON restoranlar(platform_id);
CREATE INDEX idx_urunler_restoran ON urunler(restoran_id);
CREATE INDEX idx_urunler_kategori ON urunler(kategori_id);
CREATE INDEX idx_urunler_fiyat ON urunler(fiyat);

-- =============================================
-- ÖRNEK SORGULAR
-- =============================================

-- Tüm restoranları ve ürün sayılarını gör:
-- SELECT r.ad, COUNT(u.id) as urun_sayisi
-- FROM restoranlar r
-- LEFT JOIN urunler u ON r.id = u.restoran_id
-- GROUP BY r.ad
-- ORDER BY urun_sayisi DESC;

-- Bir ürünü farklı restoranlarda karşılaştır:
-- SELECT u.ad, r.ad as restoran, u.fiyat, p.ad as platform
-- FROM urunler u
-- JOIN restoranlar r ON u.restoran_id = r.id
-- JOIN platformlar p ON r.platform_id = p.id
-- WHERE u.ad ILIKE '%tantuni%'
-- ORDER BY u.fiyat;

-- En ucuz ürünler:
-- SELECT u.ad, u.fiyat, r.ad as restoran
-- FROM urunler u
-- JOIN restoranlar r ON u.restoran_id = r.id
-- ORDER BY u.fiyat ASC
-- LIMIT 20;
