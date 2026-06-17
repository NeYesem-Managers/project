// =============================================
// Ne Yesem — PostgreSQL Veri Katmanı
// =============================================
// Backend artık verileri JSON dosyaları yerine PostgreSQL'den okuyabilir.
// USE_DB=true ayarlandığında bu modül devreye girer; aksi halde app.js
// eski JSON tabanlı okumayı kullanmaya devam eder (geri uyumluluk).

const { Pool } = require("pg");

let pool = null;

function getPool() {
  if (pool) return pool;
  pool = new Pool({
    host: process.env.DB_HOST || "localhost",
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || "ne_yesem",
    user: process.env.DB_USER || "postgres",
    password: process.env.DB_PASSWORD || "",
    max: 10,
  });
  return pool;
}

function platformToLabel(ad) {
  const v = String(ad || "").toLowerCase();
  if (v.includes("getir")) return "Getir Yemek";
  if (v.includes("yemeksepeti")) return "Yemeksepeti";
  if (v.includes("trendyol")) return "Trendyol Yemek";
  return ad || "Partner";
}

// slug/kaynak_id'den geçerli (şema içeren) bir partner URL üretir.
// Yemeksepeti tam URL'yi slug olarak saklar; Getir/Trendyol çıplak slug saklar,
// bu yüzden platforma göre tam adres kurarız (Flutter şemasız URL'leri reddediyor).
function buildPartnerUrl(slug, platformAd) {
  const raw = String(slug || "").trim();
  if (!raw) return "";
  if (/^https?:\/\//i.test(raw)) return raw; // zaten tam URL (Yemeksepeti)
  const v = String(platformAd || "").toLowerCase();
  if (v.includes("getir")) return `https://getir.com/yemek/restoran/${raw}`;
  if (v.includes("trendyol")) return `https://www.trendyolyemek.com/restoran/${raw}`;
  if (v.includes("yemeksepeti")) return `https://www.yemeksepeti.com/restaurant/${raw}`;
  return raw;
}

// app.js'deki ürün şekliyle birebir uyumlu obje üretir.
function rowToProduct(row) {
  const current = row.fiyat !== null ? Number(row.fiyat) : null;
  const original = row.orijinal_fiyat !== null ? Number(row.orijinal_fiyat) : null;
  const discount = row.indirim_yuzdesi !== null ? Number(row.indirim_yuzdesi) : 0;
  return {
    id: `db-${row.urun_id}`,
    productName: row.urun_adi,
    name: row.urun_adi,
    description: row.aciklama || "",
    category: row.kategori_adi || "Genel",
    productType: row.urun_tipi || "yemek", // YENİ: yemek/sos/icecek/ekstra/tatli
    restaurantName: row.restoran_adi,
    platform: platformToLabel(row.platform_adi),
    source: row.platform_adi,
    currentPrice: current,
    originalPrice: original,
    discountPercent: discount,
    rating: row.puan !== null ? Number(row.puan) : null,
    city: row.sehir_adi || null,
    partnerUrl: buildPartnerUrl(row.restoran_slug || row.restoran_kaynak_id, row.platform_adi),
  };
}

// Not: limit toplam ürün sayısının üzerinde tutulur ki HİÇBİR platform kırpılmasın
// (örn. Yemeksepeti + Getir + Trendyol birlikte). ORDER BY platform_id ile her
// platformdan ürünlerin belleğe alınması garanti edilir.
async function fetchProducts(limit = 200000) {
  const sql = `
    SELECT
      u.id AS urun_id, u.ad AS urun_adi, u.aciklama,
      u.fiyat, u.orijinal_fiyat, u.indirim_yuzdesi, u.urun_tipi,
      k.ad AS kategori_adi,
      r.ad AS restoran_adi, r.puan, r.slug AS restoran_slug, r.kaynak_id AS restoran_kaynak_id,
      p.ad AS platform_adi, s.ad AS sehir_adi
    FROM urunler u
    JOIN restoranlar r ON u.restoran_id = r.id
    LEFT JOIN kategoriler k ON u.kategori_id = k.id
    LEFT JOIN platformlar p ON r.platform_id = p.id
    LEFT JOIN sehirler s ON r.sehir_id = s.id
    WHERE u.musait_mi = true
    ORDER BY r.platform_id, u.id
    LIMIT $1;
  `;
  const { rows } = await getPool().query(sql, [limit]);
  return rows.map(rowToProduct);
}

async function fetchRestaurants() {
  const sql = `
    SELECT r.id, r.ad AS restoran_adi, r.puan, r.slug,
           p.ad AS platform_adi, s.ad AS sehir_adi,
           COUNT(u.id) AS urun_sayisi
    FROM restoranlar r
    LEFT JOIN platformlar p ON r.platform_id = p.id
    LEFT JOIN sehirler s ON r.sehir_id = s.id
    LEFT JOIN urunler u ON u.restoran_id = r.id
    GROUP BY r.id, p.ad, s.ad
    ORDER BY urun_sayisi DESC;
  `;
  const { rows } = await getPool().query(sql);
  return rows.map((row) => ({
    id: `db-rest-${row.id}`,
    restaurantName: row.restoran_adi,
    name: row.restoran_adi,
    platform: platformToLabel(row.platform_adi),
    city: row.sehir_adi,
    rating: row.puan !== null ? Number(row.puan) : null,
    productCount: Number(row.urun_sayisi),
    partnerUrl: row.slug || "",
  }));
}

async function ping() {
  await getPool().query("SELECT 1;");
  return true;
}

module.exports = { fetchProducts, fetchRestaurants, ping, getPool };
