require("dotenv").config();
const express = require("express");
const cors = require("cors");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const dataDir = path.join(__dirname, "../data");
const restaurantsPath = path.join(dataDir, "restaurants.json");
const getirOutputPath = path.join(dataDir, "getir_output");
const usersPath = path.join(dataDir, "users.json");
const DATA_CACHE_TTL_MS = 5 * 60 * 1000; // 5 dakika

// Şehir başına ayrı data cache
const cityCaches = new Map();
let availableCities = null;

// /compare endpoint için ayrı sonuç cache (query+city+district -> sonuç)
const compareCache = new Map();
const COMPARE_CACHE_TTL_MS = 5 * 60 * 1000;

// /search endpoint için sonuç cache (query+city+district -> sorted scored list)
const searchCache = new Map();
const SEARCH_CACHE_TTL_MS = 5 * 60 * 1000;

function readJsonFile(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) {
      return fallback;
    }
    return JSON.parse(fs.readFileSync(filePath, "utf-8"));
  } catch (error) {
    console.warn(`JSON okunamadı, atlanıyor: ${filePath}`);
    return fallback;
  }
}

function ensureUsersFile() {
  try {
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }
    if (!fs.existsSync(usersPath)) {
      fs.writeFileSync(usersPath, "[]\n", "utf-8");
    }
  } catch (error) {
    console.warn("users.json oluşturulamadı:", error.message);
  }
}

function readUsers() {
  ensureUsersFile();
  const data = readJsonFile(usersPath, []);
  if (Array.isArray(data)) {
    return data;
  }
  return Array.isArray(data.users) ? data.users : [];
}

function writeUsers(users) {
  ensureUsersFile();
  fs.writeFileSync(usersPath, `${JSON.stringify(users, null, 2)}\n`, "utf-8");
}

function hashPassword(password) {
  return crypto
    .createHash("sha256")
    .update(String(password || ""))
    .digest("hex");
}

function publicUser(user) {
  if (!user) {
    return null;
  }

  const { passwordHash, ...safeUser } = user;
  return safeUser;
}

function parsePrice(value) {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === "number") {
    return Number.isFinite(value) ? Number(value.toFixed(2)) : null;
  }

  let text = String(value).trim();
  if (!text) {
    return null;
  }

  text = text
    .replace(/₺/g, "")
    .replace(/tl/gi, "")
    .replace(/\s+/g, "")
    .replace(/[^\d,.-]/g, "");

  if (!text) {
    return null;
  }

  if (text.includes(",")) {
    text = text.replace(/\./g, "").replace(",", ".");
  } else {
    const parts = text.split(".");
    const looksLikeTurkishThousands =
      parts.length > 1 &&
      parts[0].length >= 1 &&
      parts[0].length <= 3 &&
      parts.slice(1).every((part) => part.length === 3);

    if (looksLikeTurkishThousands) {
      text = parts.join("");
    } else if (parts.length > 2) {
      const decimal = parts.pop();
      text = `${parts.join("")}.${decimal}`;
    }
  }

  const price = Number.parseFloat(text);
  return Number.isFinite(price) ? Number(price.toFixed(2)) : null;
}

function roundMoney(value) {
  if (!Number.isFinite(value)) {
    return null;
  }
  return Number(value.toFixed(2));
}

function roundPercent(value) {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Number(value.toFixed(1));
}

function normalizeName(value) {
  return String(value || "")
    .toLocaleLowerCase("tr-TR")
    .replace(/ç/g, "c")
    .replace(/ğ/g, "g")
    .replace(/ı/g, "i")
    .replace(/i̇/g, "i")
    .replace(/ö/g, "o")
    .replace(/ş/g, "s")
    .replace(/ü/g, "u")
    .replace(/[^\w\s()]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const STOP_WORDS = new Set([
  "adet",
  "ad",
  "avantaj",
  "avantajli",
  "buyuk",
  "double",
  "ekstra",
  "firsat",
  "gr",
  "gram",
  "g",
  "kg",
  "kucuk",
  "lt",
  "litre",
  "menusu",
  "menusuyle",
  "menu",
  "ml",
  "orta",
  "ozel",
  "paket",
  "porsiyon",
  "secenekli",
  "secilmis",
  "super",
  "tek",
  "ve"
]);

function tokenizeName(value) {
  const normalized = normalizeName(value).replace(/[()]/g, " ");
  return normalized
    .split(/\s+/)
    .map((token) => token.trim())
    .filter(Boolean)
    .filter((token) => token.length > 1)
    .filter((token) => !STOP_WORDS.has(token));
}

const QUERY_SYNONYMS = {
  burger: ["burger", "hamburger"],
  hamburger: ["hamburger", "burger"],
  chicken: ["chicken", "tavuk"],
  cig: ["cig", "çiğ"],
  doner: ["doner", "döner"],
  durum: ["durum", "dürüm"],
  kofte: ["kofte", "köfte"],
  pasta: ["pasta", "makarna"],
  pide: ["pide"],
  pizza: ["pizza"],
  tavuk: ["tavuk"]
};

function expandQueryTokenSets(query) {
  const tokens = tokenizeName(query);
  if (!tokens.length) {
    return [];
  }

  return tokens.map((token) => {
    const normalized = normalizeName(token);
    const aliases = QUERY_SYNONYMS[normalized] || [normalized];
    return Array.from(new Set(aliases.map(normalizeName).filter(Boolean)));
  });
}

function fieldMatchesTokenSets(field, tokenSets, mode = "all") {
  const normalizedField = normalizeName(field);
  if (!normalizedField || !tokenSets.length) {
    return false;
  }

  if (mode === "any") {
    return tokenSets.some((aliases) => aliases.some((token) => normalizedField.includes(token)));
  }

  return tokenSets.every((aliases) => aliases.some((token) => normalizedField.includes(token)));
}

const MAIN_DISH_QUERY_TOKENS = new Set([
  "burger",
  "hamburger",
  "chicken",
  "doner",
  "durum",
  "kebap",
  "kofte",
  "lahmacun",
  "pizza",
  "tavuk"
]);

const SIDE_ITEM_TOKENS = [
  "ayran",
  "baharat",
  "canta",
  "cantasi",
  "ekmek",
  "ekmegi",
  "icecek",
  "ketcap",
  "lavas",
  "mayonez",
  "patates",
  "sos",
  "soda",
  "su",
  "salgam",
  "tasima",
  "tursu"
];

function applySearchPenalty(product, query, score) {
  if (score <= 0) return score;

  const queryTokens = tokenizeName(query);
  const wantsMainDish = queryTokens.some((t) => MAIN_DISH_QUERY_TOKENS.has(t));
  if (!wantsMainDish) return score;

  const productName = normalizeName(product.productName || product.name || "");
  const queryAlreadyAsksSide = queryTokens.some((t) => SIDE_ITEM_TOKENS.includes(t));
  const looksLikeSideItem = SIDE_ITEM_TOKENS.some((t) => productName.includes(t));

  if (looksLikeSideItem && !queryAlreadyAsksSide) {
    // Yan ürün görünüyorsa ciddi ceza
    return Math.min(score, 30);
  }
  return score;
}

function productSearchScore(product, query, options = {}) {
  const normalizedQuery = normalizeName(query);
  if (!normalizedQuery) return 1;

  const tokenSets = expandQueryTokenSets(query);
  if (!tokenSets.length) return 0;

  // Pre-computed normalized fields (loadData'da hesaplandi) veya fallback
  const normalizedName = product._nName !== undefined ? product._nName : normalizeName(product.productName || product.name || '');
  const nCategory     = product._nCategory !== undefined ? product._nCategory : normalizeName(product.category || '');
  const nDescription  = options.includeDescription === false ? '' :
                        (product._nDescription !== undefined ? product._nDescription : normalizeName(product.description || ''));
  const nRestaurant   = options.includeRestaurant === false ? '' :
                        (product._nRestaurant !== undefined ? product._nRestaurant : normalizeName(product.restaurantName || ''));

  function nameIncludes(aliases) { return aliases.some((a) => normalizedName.includes(a)); }
  function catIncludes(aliases)  { return aliases.some((a) => nCategory.includes(a)); }
  function descIncludes(aliases) { return aliases.some((a) => nDescription.includes(a)); }
  function restIncludes(aliases) { return aliases.some((a) => nRestaurant.includes(a)); }

  // Pozisyon bonusu: sorgu terimi adin basinda mi? (ornk "Pizza Pogaca" > "Pogaca Pizza")
  function nameStartsWith(aliases) {
    return aliases.some((a) => normalizedName.startsWith(a + ' ') || normalizedName === a);
  }

  // --- Ad skorlamasi ---
  let nameScore = 0;
  if (normalizedName.includes(normalizedQuery)) {
    // Tam eslesme: basinda mi sonda mi?
    nameScore = nameStartsWith([normalizedQuery]) ? 105 : 100;
  } else if (tokenSets.every((aliases) => nameIncludes(aliases))) {
    nameScore = nameStartsWith(tokenSets[0]) ? 95 : 90;
  } else {
    const primaryToken = tokenSets[0];
    const primaryInName = nameIncludes(primaryToken);
    if (primaryInName) {
      const remaining = tokenSets.slice(1);
      const baseScore = nameStartsWith(primaryToken) ? 88 : 85;
      if (remaining.length === 0 || remaining.every((aliases) => nameIncludes(aliases))) {
        nameScore = baseScore;
      } else if (remaining.some((aliases) => nameIncludes(aliases))) {
        nameScore = baseScore - 7;
      } else {
        nameScore = nameStartsWith(primaryToken) ? 75 : 72;
      }
    } else if (tokenSets.some((aliases) => nameIncludes(aliases))) {
      nameScore = 50;
    }
  }

  // --- Kategori/aciklama/restoran (yalnizca ad eslesme yoksa) ---
  let fallbackScore = 0;
  if (nameScore === 0) {
    if (tokenSets.every((aliases) => catIncludes(aliases)))       fallbackScore = 38;
    else if (tokenSets.some((aliases) => catIncludes(aliases)))   fallbackScore = 28;
    else if (tokenSets.every((aliases) => descIncludes(aliases))) fallbackScore = 20;
    else if (tokenSets.some((aliases) => descIncludes(aliases)))  fallbackScore = 12;
    else if (tokenSets.every((aliases) => restIncludes(aliases))) fallbackScore = 10;
  }

  const score = nameScore > 0 ? nameScore : fallbackScore;
  if (score > 0 && nameScore === 0) {
    const primaryToken = tokenSets[0];
    if (!nameIncludes(primaryToken)) {
      return applySearchPenalty(product, query, Math.min(score, 25));
    }
  }

  return applySearchPenalty(product, query, score);
}

function groupKeyForName(value) {
  const tokens = tokenizeName(value);
  if (!tokens.length) {
    return normalizeName(value);
  }

  const words = tokens.filter((token) => !/^\d+$/.test(token));
  const numbers = tokens.filter((token) => /^\d+$/.test(token));
  const selectedWords = Array.from(new Set(words)).slice(0, 4).sort();
  const selectedNumbers = numbers.slice(0, 1);
  return [...selectedWords, ...selectedNumbers].join(" ");
}

function compactProduct(product) {
  return {
    id: product.id,
    productName: product.productName,
    restaurantName: product.restaurantName,
    platform: product.platform,
    currentPrice: product.currentPrice,
    originalPrice: product.originalPrice,
    discountPercent: product.discountPercent,
    partnerUrl: product.partnerUrl,
    category: product.category
  };
}

function sourceLabel(source) {
  const value = normalizeName(source);
  if (value.includes("getir")) {
    return "Getir Yemek";
  }
  if (value.includes("yemeksepeti")) {
    return "Yemeksepeti";
  }
  return source || "Partner";
}

function getRestaurantArray(data) {
  if (Array.isArray(data)) {
    return data;
  }
  if (Array.isArray(data.restaurants)) {
    return data.restaurants;
  }
  if (Array.isArray(data.data)) {
    return data.data;
  }
  if (Array.isArray(data.items)) {
    return data.items;
  }
  return [];
}

function normalizeYemeksepetiRestaurants(data) {
  const restaurants = getRestaurantArray(data);
  const products = [];
  const normalizedRestaurants = [];

  restaurants.forEach((restaurant, restaurantIndex) => {
    const restaurantName =
      restaurant.restoran_adi ||
      restaurant.name ||
      restaurant.restaurant_name ||
      restaurant.title ||
      `Restoran ${restaurantIndex + 1}`;

    const restaurantRating =
      restaurant.puan ||
      restaurant.rating ||
      restaurant.score ||
      null;

    const address = restaurant.adres || restaurant.address || "";
    const restaurantUrl =
      restaurant.url ||
      restaurant.link ||
      "https://www.yemeksepeti.com/";

    normalizedRestaurants.push({
      id: `ys-restaurant-${restaurantIndex}`,
      restaurantName,
      restaurantRating,
      address,
      platform: "Yemeksepeti",
      partnerUrl: restaurantUrl
    });

    const menu =
      restaurant.menu_urunleri ||
      restaurant.menu ||
      restaurant.items ||
      restaurant.products ||
      restaurant.urunler ||
      restaurant.categories ||
      [];

    if (!Array.isArray(menu)) {
      return;
    }

    menu.forEach((item, itemIndex) => {
      const productName =
        item.isim ||
        item.name ||
        item.item_name ||
        item.urun_adi ||
        item.title ||
        "Ürün";

      const hasDiscountPrice =
        item.indirimli_fiyat !== undefined &&
        item.indirimli_fiyat !== null &&
        String(item.indirimli_fiyat).trim() !== "";

      const rawCurrentPrice =
        item.indirimli_fiyat ||
        item.price ||
        item.fiyat ||
        item.current_price ||
        item.currentPrice ||
        item.indirimsiz_fiyat ||
        null;

      const currentPrice = parsePrice(rawCurrentPrice);
      const originalPrice = hasDiscountPrice
        ? parsePrice(item.indirimsiz_fiyat || item.original_price || item.orijinal_fiyat)
        : parsePrice(item.original_price || item.orijinal_fiyat);

      const normalizedName = normalizeName(productName);
      const product = {
        id: `${restaurantIndex}-${itemIndex}`,
        productName,
        normalizedName,
        restaurantName,
        restaurantRating,
        address,
        platform: "Yemeksepeti",
        currentPrice,
        originalPrice,
        discountAmount: 0,
        discountPercent: 0,
        isSuspiciousDiscount: false,
        suspicionReason: "Analiz bekleniyor.",
        cheaperAlternatives: [],
        partnerUrl: item.url || item.link || restaurantUrl,
        description: item.aciklama || item.description || "",
        category: item.kategori || item.category || item.categoryName || "Genel",
        productType: item.urun_tipi || item.productType || "yemek",
        image: item.image || item.image_url || item.gorsel_url || null,
        tokens: tokenizeName(productName),
        groupKey: groupKeyForName(productName),
        source: "yemeksepeti"
      };

      products.push(addLegacyProductAliases(product));
    });
  });

  return { restaurants: normalizedRestaurants, products };
}

function findJsonFiles(rootDir) {
  const files = [];

  function walk(dir) {
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (error) {
      return;
    }

    entries.forEach((entry) => {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (
        entry.isFile() &&
        entry.name.endsWith(".json") &&
        !entry.name.startsWith(".")
      ) {
        files.push(fullPath);
      }
    });
  }

  if (fs.existsSync(rootDir)) {
    walk(rootDir);
  }

  return files;
}

function getGetirMenuCategories(restaurant) {
  const menu = restaurant.menu;
  if (menu && Array.isArray(menu.categories)) {
    return menu.categories;
  }
  if (Array.isArray(menu)) {
    return menu;
  }
  if (Array.isArray(restaurant.categories)) {
    return restaurant.categories;
  }
  if (Array.isArray(restaurant.menu_categories)) {
    return restaurant.menu_categories;
  }
  return [];
}

function parseDiscountPercentFromRestaurant(restaurant) {
  const discounts = Array.isArray(restaurant.discounts) ? restaurant.discounts : [];
  for (const discount of discounts) {
    const text = `${discount.description || ""} ${discount.title || ""} ${discount.name || ""}`;
    const match = text.match(/%(\d+(?:[,.]\d+)?)/);
    if (match) {
      const value = parsePrice(match[1]);
      if (value && value > 0 && value < 90) {
        return value;
      }
    }
  }
  return null;
}

function buildGetirPartnerUrl(restaurant) {
  if (restaurant.url || restaurant.link || restaurant.web_url || restaurant.deep_link) {
    return restaurant.url || restaurant.link || restaurant.web_url || restaurant.deep_link;
  }
  if (restaurant.slug) {
    return `https://getir.com/yemek/restoran/${restaurant.slug}`;
  }
  return "https://getir.com/yemek/";
}

// Getir dizin yapısından şehirleri bul (output/ankara, output/bursa, ...)
function findGetirCities() {
  const outputDir = path.join(getirOutputPath, "output");
  if (!fs.existsSync(outputDir)) return [];
  try {
    return fs.readdirSync(outputDir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name.toLowerCase());
  } catch {
    return [];
  }
}

function getAvailableCities() {
  if (availableCities) return availableCities;
  const getirCities = findGetirCities();
  const ysData = readJsonFile(restaurantsPath, []);
  const ysArr = Array.isArray(ysData) ? ysData : (ysData.restaurants || ysData.data || []);
  const ysCities = new Set();
  ysArr.forEach((r) => {
    const adres = (r.adres || r.address || "").trim();
    if (adres) {
      const parts = adres.split(/\s+/);
      const city = parts[parts.length - 1]?.toLowerCase();
      if (city && city.length > 2 && city !== "bulunamadı") ysCities.add(city);
    }
  });
  const allCities = [...new Set([...getirCities, ...ysCities])];
  availableCities = allCities.length ? allCities : ["istanbul", "ankara", "izmir", "bursa"];
  return availableCities;
}

// Slug'dan ilçe ismi çıkar
// Örn: 'ada-doner-cankaya-bahcelievler-mah-cankaya-ankara' -> 'cankaya'
// Slug sonu: ...-ilce-sehir veya ...-ilce-sehir-N
function extractDistrictFromSlug(slug, city) {
  if (!slug || !city) return null;
  const cityKey = city.toLowerCase().replace(/\s/g, "-").replace(/[\u0131]/g, "i").replace(/[\u015f]/g, "s");
  // Numara sonekini temizle (-2, -3 vs)
  let s = slug.replace(/-\d+$/, "");
  // Sehiri sondan cıkar
  if (s.endsWith("-" + cityKey)) {
    s = s.slice(0, -(cityKey.length + 1));
  }
  // Son kelime ilce olur (cankaya, mamak, nilufer vb)
  const parts = s.split("-").filter(Boolean);
  return parts.length > 0 ? parts[parts.length - 1] : null;
}

// Bir sehirdeki tum ilceleri bul (Getir slug'larindan)
const districtCache = new Map();
function getAvailableDistricts(city) {
  if (!city) return [];
  const cityKey = city.toLowerCase();
  if (districtCache.has(cityKey)) return districtCache.get(cityKey);

  const cityDir = path.join(getirOutputPath, "output", cityKey, "getir_yemek");
  if (!fs.existsSync(cityDir)) {
    districtCache.set(cityKey, []);
    return [];
  }
  const counts = {};
  try {
    const files = fs.readdirSync(cityDir).filter((f) => f.endsWith(".json"));
    files.forEach((f) => {
      let raw = readJsonFile(path.join(cityDir, f), null);
      if (raw && raw.getir_yemek) raw = raw.getir_yemek;
      if (!raw || !raw.slug) return;
      const d = extractDistrictFromSlug(raw.slug, cityKey);
      if (d && d.length > 2) counts[d] = (counts[d] || 0) + 1;
    });
  } catch (_) {}

  const districts = Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .map(([key, count]) => ({
      key,
      label: key.charAt(0).toUpperCase() + key.slice(1).replace(/-/g, " "),
      count
    }));
  districtCache.set(cityKey, districts);
  return districts;
}

function normalizeGetirOutput(filterCity, filterDistrict) {
  // filterCity verilmisse sadece o sehirin dosyalarini oku
  let searchRoot = getirOutputPath;
  if (filterCity) {
    const cityPath = path.join(getirOutputPath, "output", filterCity.toLowerCase());
    if (fs.existsSync(cityPath)) {
      searchRoot = cityPath;
    }
  }
  const files = findJsonFiles(searchRoot);
  const restaurants = [];
  const products = [];

  files.forEach((filePath, fileIndex) => {
    // Getir JSON'u iki farklı format olabilir: {getir_yemek: {...}} veya doğrudan nesne
    let rawRestaurant = readJsonFile(filePath, null);
    // Üst düzey alan getir_yemek ise içine gir
    if (rawRestaurant && typeof rawRestaurant === "object" && !Array.isArray(rawRestaurant) && rawRestaurant.getir_yemek) {
      rawRestaurant = rawRestaurant.getir_yemek;
    }
    const restaurant = rawRestaurant;
    if (!restaurant || typeof restaurant !== "object" || Array.isArray(restaurant)) {
      return;
    }
    // Şehir ve İLÇE bilgisini dosya yolundan/slug'dan çıkar
    const cityFromPath = (() => {
      const rel = filePath.replace(getirOutputPath, "").replace(/\\/g, "/");
      const parts = rel.split("/").filter(Boolean);
      const idx = parts.indexOf("output");
      return idx >= 0 && parts[idx + 1] ? parts[idx + 1] : null;
    })();
    const restaurantCity = cityFromPath || null;
    const restaurantDistrict = extractDistrictFromSlug(restaurant.slug, restaurantCity) || null;

    // İlçe filtresi: verilmişse sadece o ilçenin restoranlarını al
    if (filterDistrict && restaurantDistrict !== filterDistrict.toLowerCase()) {
      return;
    }

    const categories = getGetirMenuCategories(restaurant);
    if (!categories.length) {
      return;
    }

    const restaurantName =
      restaurant.name ||
      restaurant.restaurantName ||
      restaurant.restaurant_name ||
      restaurant.title ||
      `Getir Restoran ${fileIndex + 1}`;

    const restaurantRating =
      restaurant.rating ||
      restaurant.score ||
      restaurant.rate ||
      null;

    const address =
      restaurant.address ||
      restaurant.full_address ||
      restaurant.location?.address ||
      restaurant.neighborhood ||
      "";

    const partnerUrl = buildGetirPartnerUrl(restaurant);
    const platform = sourceLabel(restaurant.source || "getir_yemek");
    const restaurantDiscountPercent = parseDiscountPercentFromRestaurant(restaurant);

    restaurants.push({
      id: `getir-restaurant-${fileIndex}`,
      restaurantName,
      restaurantRating,
      address,
      city: restaurantCity,
      district: restaurantDistrict,
      platform,
      partnerUrl
    });

    categories.forEach((category, categoryIndex) => {
      const categoryName = category.name || category.title || category.category || "Genel";
      const items =
        category.items ||
        category.products ||
        category.urunler ||
        category.children ||
        [];

      if (!Array.isArray(items)) {
        return;
      }

      items.forEach((item, itemIndex) => {
        const productName =
          item.name ||
          item.isim ||
          item.item_name ||
          item.urun_adi ||
          item.title ||
          "Ürün";

        const currentPrice = parsePrice(
          item.price ||
            item.current_price ||
            item.currentPrice ||
            item.fiyat ||
            item.indirimli_fiyat
        );

        const itemDiscountPercent = parsePrice(
          item.discount_percentage ||
            item.discountPercent ||
            item.discount_rate ||
            item.discountRate
        );

        let originalPrice = parsePrice(
          item.original_price ||
            item.originalPrice ||
            item.indirimsiz_fiyat ||
            item.orijinal_fiyat ||
            item.struck_price
        );

        const effectiveDiscountPercent = itemDiscountPercent || restaurantDiscountPercent;
        if (!originalPrice && currentPrice && effectiveDiscountPercent > 0 && effectiveDiscountPercent < 90) {
          originalPrice = roundMoney(currentPrice / (1 - effectiveDiscountPercent / 100));
        }

        const normalizedName = normalizeName(productName);
        const product = {
          id: `getir-${fileIndex}-${categoryIndex}-${itemIndex}`,
          productName,
          normalizedName,
          restaurantName,
          restaurantRating,
          address,
          city: restaurantCity,
          district: restaurantDistrict,
          platform,
          currentPrice,
          originalPrice,
          discountAmount: 0,
          discountPercent: 0,
          isSuspiciousDiscount: false,
          suspicionReason: "Analiz bekleniyor.",
          cheaperAlternatives: [],
          partnerUrl: item.url || item.link || partnerUrl,
          description: item.description || item.aciklama || "",
          category: categoryName,
          image: item.image_url || item.image || item.gorsel_url || "",
          tokens: tokenizeName(productName),
          groupKey: groupKeyForName(productName),
          source: "getir"
        };

        products.push(addLegacyProductAliases(product));
      });
    });
  });

  return { restaurants, products, fileCount: files.length };
}

function addLegacyProductAliases(product) {
  return {
    ...product,
    name: product.productName,
    price: product.currentPrice,
    rating: product.restaurantRating
  };
}

function analyzeProducts(products) {
  const groups = new Map();

  products.forEach((product) => {
    if (!product.groupKey || product.currentPrice === null || product.currentPrice <= 0) {
      return;
    }
    if (!groups.has(product.groupKey)) {
      groups.set(product.groupKey, []);
    }
    groups.get(product.groupKey).push(product);
  });

  groups.forEach((group) => {
    group.sort((a, b) => a.currentPrice - b.currentPrice);
  });

  products.forEach((product) => {
    const group = groups.get(product.groupKey) || [];
    const pricedGroup = group.filter((item) => item.currentPrice !== null);
    const peers = pricedGroup.filter((item) => item.id !== product.id);
    const marketAverage =
      pricedGroup.length > 1
        ? pricedGroup.reduce((sum, item) => sum + item.currentPrice, 0) / pricedGroup.length
        : null;

    const cheaperAlternatives = peers
      .filter((item) => item.currentPrice < product.currentPrice - 0.01)
      .sort((a, b) => a.currentPrice - b.currentPrice)
      .slice(0, 3)
      .map(compactProduct);

    let discountAmount = 0;
    let discountPercent = 0;
    if (
      product.originalPrice !== null &&
      product.currentPrice !== null &&
      product.originalPrice > product.currentPrice
    ) {
      discountAmount = roundMoney(product.originalPrice - product.currentPrice) || 0;
      discountPercent = roundPercent((discountAmount / product.originalPrice) * 100);
    }

    const reasons = [];

    // Demo amaçlı heuristic: gerçek fiyat geçmişi olmadığı için ürünleri benzer isimli ürünlerin güncel fiyatlarıyla kıyaslıyoruz.
    if (discountAmount > 0 && discountPercent < 5) {
      reasons.push("Düşük indirim - sahte indirim şüphesi");
    }

    if (
      product.currentPrice !== null &&
      marketAverage !== null &&
      product.currentPrice > marketAverage &&
      discountAmount > 0
    ) {
      reasons.push("Benzer ürünlere göre pahalı - sahte indirim şüphesi");
    }

    if (
      discountAmount > 0 &&
      cheaperAlternatives.length > 0 &&
      product.currentPrice > cheaperAlternatives[0].currentPrice * 1.05
    ) {
      reasons.push("İndirimli görünmesine rağmen daha ucuz alternatif var");
    }

    const isBestInGroup =
      product.currentPrice !== null &&
      pricedGroup.length > 1 &&
      pricedGroup[0]?.id === product.id;

    const belowAverageDeal =
      product.currentPrice !== null &&
      marketAverage !== null &&
      product.currentPrice <= marketAverage * 0.95;

    const isSuspiciousDiscount = reasons.length > 0;
    const dealScore =
      !isSuspiciousDiscount && product.currentPrice !== null
        ? roundPercent(
            Math.max(discountPercent, 0) +
              (belowAverageDeal ? ((marketAverage - product.currentPrice) / marketAverage) * 100 : 0) +
              (isBestInGroup ? 12 : 0)
          )
        : 0;

    Object.assign(product, {
      discountAmount,
      discountPercent,
      isSuspiciousDiscount,
      suspicionReason: isSuspiciousDiscount
        ? Array.from(new Set(reasons)).join(" • ")
        : discountAmount > 0 || belowAverageDeal
          ? "Gerçek avantaj gibi görünüyor."
          : "Belirgin sahte indirim sinyali yok.",
      cheaperAlternatives,
      marketAveragePrice: marketAverage ? roundMoney(marketAverage) : null,
      isBestInGroup,
      dealScore
    });
  });

  return products;
}

function stripInternalFields(product) {
  const { tokens, groupKey, source, ...publicProduct } = product;
  return publicProduct;
}

const USE_DB = String(process.env.USE_DB || "").toLowerCase() === "true";
let dbLayer = null;
let dbProductsCache = null; // DB'den çekilen ham ürünler (groupKey eklenmeden önce)
let dbRestaurantsCache = null;

if (USE_DB) {
  try {
    dbLayer = require("./db");
  } catch (error) {
    console.warn("pg modülü yüklenemedi, JSON moduna düşülüyor:", error.message);
  }
}

// DB'den ürünleri çekip belleğe alır (asenkron). Route'lar senkron çalışır,
// bu yüzden veriyi periyodik olarak önceden yükleriz.
async function refreshDbCache() {
  if (!dbLayer) return;
  try {
    const [products, restaurants] = await Promise.all([
      dbLayer.fetchProducts(),
      dbLayer.fetchRestaurants(),
    ]);
    // app.js pipeline'ının beklediği alanları ekle (groupKey, tokens vb.)
    dbProductsCache = products.map((p) => ({
      ...p,
      groupKey: groupKeyForName(p.productName || p.name || ""),
    }));
    dbRestaurantsCache = restaurants;
    dataCache = null; // bir sonraki loadData yeniden hesaplasın
    console.log(`[DB] ${dbProductsCache.length} ürün, ${dbRestaurantsCache.length} restoran belleğe alındı.`);
  } catch (error) {
    console.warn("[DB] Yenileme hatası, JSON fallback kullanılacak:", error.message);
  }
}

// Yemeksepeti restoranının şehirini adresin son kelimesinden çıkar
function extractCityFromAddress(address) {
  if (!address) return null;
  const parts = address.trim().split(/\s+/);
  const city = parts[parts.length - 1]?.toLowerCase();
  if (!city || city.length <= 2 || city === "bulunamadı") return null;
  return city;
}

function loadData(city, district) {
  // Normalize
  const cityKey = city ? city.toLowerCase().trim() : "all";
  const districtKey = district ? district.toLowerCase().trim() : "";
  const cacheKey = districtKey ? `${cityKey}::${districtKey}` : cityKey;
  const now = Date.now();

  const cached = cityCaches.get(cacheKey);
  if (cached && now - cached.loadedAt < DATA_CACHE_TTL_MS) {
    return cached.data;
  }

  let baseProducts;
  let baseRestaurants;
  let sources;

  if (USE_DB && dbProductsCache && dbProductsCache.length) {
    let prods = dbProductsCache;
    let rests = dbRestaurantsCache || [];
    if (cityKey !== "all") {
      prods = prods.filter((p) => (p.city || "").toLowerCase() === cityKey);
      rests = rests.filter((r) => (r.city || "").toLowerCase() === cityKey);
    }
    if (districtKey) {
      prods = prods.filter((p) => (p.district || "").toLowerCase() === districtKey);
      rests = rests.filter((r) => (r.district || "").toLowerCase() === districtKey);
    }
    baseProducts = prods;
    baseRestaurants = rests;
    sources = ["PostgreSQL (ne_yesem)"];
  } else {
    const yemeksepetiData = readJsonFile(restaurantsPath, []);
    const yemeksepeti = normalizeYemeksepetiRestaurants(yemeksepetiData);

    // YS: şehir + ilçe filtresi
    let ysProds = yemeksepeti.products;
    let ysRests = yemeksepeti.restaurants;
    if (cityKey !== "all") {
      ysProds = ysProds.filter((p) => extractCityFromAddress(p.address) === cityKey);
      ysRests = ysRests.filter((r) => extractCityFromAddress(r.address) === cityKey);
    }
    if (districtKey) {
      // YS adresinden ilçe: 'YILDIRIM/BURSA' formatı → ilçe = YILDIRIM
      const extractYsDistrict = (addr) => {
        const m = (addr || "").match(/([A-Za-z\u00c0-\u024f]+)\s*\/\s*[A-Za-z\u00c0-\u024f]+\s*$/i);
        return m ? m[1].toLowerCase().replace(/\s/g, "-") : null;
      };
      ysProds = ysProds.filter((p) => extractYsDistrict(p.address) === districtKey);
      ysRests = ysRests.filter((r) => extractYsDistrict(r.address) === districtKey);
    }

    // Getir: şehir + ilçe filtresini normalizer'da uygula (disk I/O'dan önce)
    const getir = normalizeGetirOutput(
      cityKey !== "all" ? cityKey : null,
      districtKey || null
    );
    baseProducts = [...ysProds, ...getir.products];
    baseRestaurants = [...ysRests, ...getir.restaurants];
    sources = ["Yemeksepeti scraper JSON"];
    if (getir.fileCount > 0 && getir.products.length > 0) {
      sources.push("Getir scraper output");
    }
  }

  // Arama icin normalized alanlar onceden hesaplanir (her urun icin 1 kez)
  // productSearchScore bu alanlari okur -> normalizeName tekrar cagrilmaz
  const products = analyzeProducts(baseProducts).map((p) => {
    const s = stripInternalFields(p);
    s._nName = normalizeName(s.productName || s.name || '');
    s._nCategory = normalizeName(s.category || '');
    s._nDescription = normalizeName(s.description || '');
    s._nRestaurant = normalizeName(s.restaurantName || '');
    return s;
  });
  const restaurants = baseRestaurants;
  const suspiciousDiscounts = products.filter((product) => product.isSuspiciousDiscount);
  const MIN_DEAL_PRICE = 30;
  const deals = products
    .filter((product) => product.currentPrice !== null && product.currentPrice >= MIN_DEAL_PRICE)
    .filter((product) => !product.isSuspiciousDiscount)
    .filter((product) => product.dealScore > 0 || product.discountPercent >= 5)
    .sort((a, b) => b.dealScore - a.dealScore || a.currentPrice - b.currentPrice);

  const data = {
    restaurants,
    products,
    suspiciousDiscounts,
    deals,
    sources,
    city: cityKey,
    district: districtKey || null,
    getirFileCount: 0,
  };

  cityCaches.set(cacheKey, { loadedAt: now, data });
  return data;
}

function getLimit(req, defaultLimit, maxLimit) {
  const rawLimit = Number.parseInt(req.query.limit, 10);
  if (!Number.isFinite(rawLimit) || rawLimit <= 0) {
    return defaultLimit;
  }
  return Math.min(rawLimit, maxLimit);
}

function getOffset(req) {
  const page = Number.parseInt(req.query.page, 10);
  const limit = getLimit(req, 20, 100);
  if (!Number.isFinite(page) || page <= 1) {
    return 0;
  }
  return (page - 1) * limit;
}

function queryMatchesProduct(product, query, options = {}) {
  return productSearchScore(product, query, options) > 0;
}

// Request'ten sehir parametresini al (yoksa 'all')
function getCityParam(req) {
  const raw = String(req.query.city || req.query.sehir || "").trim().toLowerCase();
  return raw || "all";
}

// Request'ten ilce parametresini al
function getDistrictParam(req) {
  const raw = String(req.query.district || req.query.ilce || "").trim().toLowerCase();
  return raw || "";
}

function compareProducts(query, city, district) {
  const cacheKey = `${city || 'all'}::${district || ''}::${query.toLowerCase().trim()}`;
  const now = Date.now();
  const cached = compareCache.get(cacheKey);
  if (cached && now - cached.loadedAt < COMPARE_CACHE_TTL_MS) {
    return cached.result;
  }

  const { products } = loadData(city, district);
  // Sadece anlamli fiyatli urunlerde text scoring yap
  const candidates = products.filter(
    (p) => p.currentPrice !== null && p.currentPrice >= 30
  );
  const scoredProducts = candidates
    .map((product) => ({
      ...product,
      searchScore: productSearchScore(product, query, {
        includeRestaurant: false,
        includeDescription: true
      })
    }))
    .filter((product) => product.searchScore > 0);

  const nameMatches = scoredProducts.filter((product) => product.searchScore >= 80);
  const strongMatches = scoredProducts.filter((product) => product.searchScore >= 55);
  const matches = (nameMatches.length ? nameMatches : strongMatches.length ? strongMatches : scoredProducts).sort(
    (a, b) => a.currentPrice - b.currentPrice || b.searchScore - a.searchScore
  );

  const bestDeal = matches[0] || null;
  const bestPrice = bestDeal?.currentPrice || null;
  const results = matches.map((product, index) => {
    const compareSuspicious =
      index > 0 &&
      bestPrice !== null &&
      product.discountPercent > 0 &&
      product.currentPrice > bestPrice * 1.1;

    return {
      ...product,
      isBestDeal: index === 0,
      compareSuspicious,
      compareLabel:
        index === 0
          ? "En iyi fiyat"
          : compareSuspicious || product.isSuspiciousDiscount
            ? "Sahte indirim şüphesi"
            : "Daha pahalı"
    };
  });

  const result = {
    query,
    count: results.length,
    bestDeal: results[0] || null,
    suspicious: results.filter((product) => product.compareSuspicious || product.isSuspiciousDiscount),
    results
  };

  compareCache.set(cacheKey, { loadedAt: now, result });
  return result;
}

function asyncRoute(handler) {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

app.get("/", (req, res) => {
  res.json({
    message: "NeYesem Demo Backend çalışıyor",
    endpoints: [
      "/api/health",
      "/api/cities",
      "/api/restaurants?city=bursa",
      "/api/deals?city=bursa&sort=price_asc&page=1&limit=20",
      "/api/search?q=burger&city=istanbul",
      "/api/products?city=ankara",
      "/api/products/:id",
      "/api/products/:id/analysis",
      "/api/compare?query=tavuk&city=izmir",
      "/api/suspicious-discounts?city=bursa",
      "/api/auth/register",
      "/api/auth/login",
      "/api/profile/:userId"
    ]
  });
});

// Mevcut şehirleri listele
app.get("/api/cities", (req, res) => {
  const cities = getAvailableCities();
  const labels = {
    istanbul: "İstanbul", ankara: "Ankara", izmir: "İzmir", bursa: "Bursa",
    antalya: "Antalya", adana: "Adana", konya: "Konya"
  };
  res.json(
    cities.map((c) => ({ key: c, label: labels[c] || c.charAt(0).toUpperCase() + c.slice(1) }))
  );
});

// Bir şehirin ilçelerini listele
app.get("/api/districts", (req, res) => {
  const city = getCityParam(req);
  if (city === "all" || !city) {
    return res.status(400).json({ message: "Şehir seçmelisiniz. Örnek: /api/districts?city=ankara" });
  }
  const districts = getAvailableDistricts(city);
  res.json(districts);
});

app.get("/api/health", (req, res) => {
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const { restaurants, products, suspiciousDiscounts, deals, sources } = loadData(
    city === "all" ? null : city,
    district || null
  );
  const users = readUsers();
  res.json({
    status: "ok",
    city,
    district: district || null,
    sources,
    restaurantCount: restaurants.length,
    productCount: products.length,
    suspiciousDiscountCount: suspiciousDiscounts.length,
    dealCount: deals.length,
    userCount: users.length
  });
});

app.get("/api/restaurants", (req, res) => {
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const { restaurants } = loadData(city === "all" ? null : city, district || null);
  res.json(restaurants.slice(0, getLimit(req, 50, 500)));
});

app.get("/api/products", (req, res) => {
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const { products } = loadData(city === "all" ? null : city, district || null);
  const type = String(req.query.type || "all").toLowerCase();
  const sortBy = String(req.query.sort || "").toLowerCase();
  const minPrice = parseFloat(req.query.minPrice) || 0;
  const maxPrice = parseFloat(req.query.maxPrice) || Infinity;
  let list = products.filter((p) => p.currentPrice !== null && p.currentPrice >= 30);
  if (type !== "all") list = list.filter((p) => (p.productType || "yemek") === type);
  if (minPrice > 0) list = list.filter((p) => p.currentPrice >= minPrice);
  if (maxPrice < Infinity) list = list.filter((p) => p.currentPrice <= maxPrice);
  if (sortBy === "price_asc") list = list.sort((a, b) => a.currentPrice - b.currentPrice);
  else if (sortBy === "price_desc") list = list.sort((a, b) => b.currentPrice - a.currentPrice);
  else if (sortBy === "discount") list = list.sort((a, b) => b.discountPercent - a.discountPercent);
  const limit = getLimit(req, 20, 100);
  const offset = getOffset(req);
  const total = list.length;
  const page = Number.parseInt(req.query.page, 10) || 1;
  res.json({ items: list.slice(offset, offset + limit), total, page, totalPages: Math.ceil(total / limit), limit });
});

function resolveProductLocation(productId, req) {
  let city = getCityParam(req);
  let district = getDistrictParam(req);

  // Eger sehir belirtilmediyse, aktif cache'lerden veya DB'den urunu bulup konumunu otomatik belirle
  if (city === "all" && !district) {
    for (const [key, cache] of cityCaches.entries()) {
      if (cache && cache.data && cache.data.products) {
        const match = cache.data.products.find((p) => String(p.id) === String(productId));
        if (match) {
          const parts = key.split("::");
          city = parts[0] === "all" ? null : parts[0];
          district = parts[1] || null;
          return { city, district };
        }
      }
    }

    if (USE_DB && dbProductsCache) {
      const rawProd = dbProductsCache.find((p) => String(p.id) === String(productId));
      if (rawProd) {
        city = rawProd.city ? rawProd.city.toLowerCase() : null;
        district = rawProd.district ? rawProd.district.toLowerCase() : null;
        return { city, district };
      }
    }
  }

  return {
    city: city === "all" ? null : city,
    district: district || null
  };
}

app.get("/api/products/:id", (req, res) => {
  const { city, district } = resolveProductLocation(req.params.id, req);
  const { products } = loadData(city, district);
  const product = products.find((item) => String(item.id) === String(req.params.id));
  if (!product) {
    return res.status(404).json({ message: "Ürün bulunamadı" });
  }
  res.json(product);
});

app.get("/api/products/:id/analysis", (req, res) => {
  const { city, district } = resolveProductLocation(req.params.id, req);
  const { products } = loadData(city, district);
  const product = products.find((item) => String(item.id) === String(req.params.id));

  if (!product) {
    return res.status(404).json({ message: "Ürün bulunamadı" });
  }

  res.json({
    product,
    analysis: {
      currentPrice: product.currentPrice,
      originalPrice: product.originalPrice,
      discountAmount: product.discountAmount,
      discountPercent: product.discountPercent,
      isSuspiciousDiscount: product.isSuspiciousDiscount,
      suspicionReason: product.suspicionReason,
      marketAveragePrice: product.marketAveragePrice,
      cheaperAlternatives: product.cheaperAlternatives
    }
  });
});

// Arama sonuclarini cache'le (query+city+district → {loadedAt, tuples})
// tuple format: [score, productRef] — obje kopyasi yok, referans tutuluyor
function searchProducts(query, city, district) {
  const cacheKey = `${city || 'all'}::${district || ''}::${normalizeName(query)}`;
  const now = Date.now();
  const cached = searchCache.get(cacheKey);
  if (cached && now - cached.loadedAt < SEARCH_CACHE_TTL_MS) {
    return cached.tuples;
  }
  const { products } = loadData(city === 'all' ? null : city, district || null);
  // Spread ({...p}) yerine [score, ref] tuple'i kullan — 15k obje kopyasından kacin
  const tuples = [];
  for (const p of products) {
    if (p.currentPrice === null || p.currentPrice < 30) continue;
    const score = productSearchScore(p, query);
    if (score > 0) tuples.push([score, p]);
  }
  tuples.sort((a, b) => b[0] - a[0] || a[1].currentPrice - b[1].currentPrice);
  searchCache.set(cacheKey, { loadedAt: now, tuples });
  return tuples;
}

app.get("/api/search", (req, res) => {
  const q = req.query.q || "";
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const sortBy = String(req.query.sort || "").toLowerCase();
  const minPrice = parseFloat(req.query.minPrice) || 0;
  const maxPrice = parseFloat(req.query.maxPrice) || Infinity;

  // Tuple listesi: [[score, productRef], ...] (cache'den veya hesaplanir)
  let tuples = searchProducts(q, city, district);

  // Fiyat filtresi — sadece bu request icin yeni dizi, cache bozulmaz
  if (minPrice > 0 || maxPrice < Infinity) {
    tuples = tuples.filter(([, p]) =>
      (minPrice <= 0 || p.currentPrice >= minPrice) &&
      (maxPrice >= Infinity || p.currentPrice <= maxPrice)
    );
  }

  // Kullanici baska siralama sectiyse override (shallow copy yeterli)
  if (sortBy === "price_asc") {
    tuples = [...tuples].sort(([, a], [, b]) => a.currentPrice - b.currentPrice);
  } else if (sortBy === "price_desc") {
    tuples = [...tuples].sort(([, a], [, b]) => b.currentPrice - a.currentPrice);
  } else if (sortBy === "discount") {
    tuples = [...tuples].sort(([, a], [, b]) => b.discountPercent - a.discountPercent);
  }

  const limit = getLimit(req, 20, 100);
  const offset = getOffset(req);
  const total = tuples.length;
  const page = Number.parseInt(req.query.page, 10) || 1;

  // Sadece sayfa boyutu kadar (max 20) urun objesi olustur
  const items = tuples.slice(offset, offset + limit).map(([, p]) => p);
  res.json({ items, total, page, totalPages: Math.ceil(total / limit), limit });
});


app.get("/api/recommendations", (req, res) => {
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const { deals, products } = loadData(city === "all" ? null : city, district || null);
  const sourceProducts = deals.length
    ? deals
    : products.filter((product) => product.currentPrice !== null && product.currentPrice > 0);
  const recommendations = sourceProducts
    .slice(0, getLimit(req, 12, 50))
    .map((product, index) => ({
      ...product,
      aiLabel: index % 2 === 0 ? "AI Öneri" : "Popüler Seçim",
      reason: product.isSuspiciousDiscount
        ? product.suspicionReason
        : "Scraper çıktısından alınan gerçek restoran ve ürün verileriyle öneri oluşturuldu."
    }));
  res.json(recommendations);
});

// IP'den şehir + ilçe tespiti — sunucu tarafında dış servislere istek yapılır
// Mobil cihazdan çalışmayan ipapi.co gibi servisler için güvenilir alternatif
app.get("/api/geo-city", asyncRoute(async (req, res) => {
  // İstemcinin IP'sini al (proxy arkasındaysa X-Forwarded-For'dan)
  const clientIp =
    (req.headers["x-forwarded-for"] || "").split(",")[0].trim() ||
    req.socket?.remoteAddress ||
    "";

  const cities = getAvailableCities();

  function normalizeGeo(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/ç/g, "c")
      .replace(/ğ/g, "g")
      .replace(/ı/g, "i")
      .replace(/i̇/g, "i")
      .replace(/ö/g, "o")
      .replace(/ş/g, "s")
      .replace(/ü/g, "u")
      .replace(/[^a-z0-9]/g, "")
      .trim();
  }

  function matchCity(rawCity) {
    if (!rawCity) return null;
    const norm = normalizeGeo(rawCity);
    for (const c of cities) {
      if (normalizeGeo(c) === norm) return c;
    }
    for (const c of cities) {
      const ck = normalizeGeo(c);
      if (norm.includes(ck) || ck.includes(norm)) return c;
    }
    return null;
  }

  // IP city alanından ilçe eşleştirme
  function matchDistrict(cityKey, rawDistrictHint) {
    if (!cityKey || !rawDistrictHint) return null;
    const districts = getAvailableDistricts(cityKey);
    if (!districts.length) return null;
    const norm = normalizeGeo(rawDistrictHint);
    // Tam eşleşme
    for (const d of districts) {
      if (normalizeGeo(d.key) === norm || normalizeGeo(d.label) === norm) {
        return d;
      }
    }
    // İçerme kontrolü
    for (const d of districts) {
      const dk = normalizeGeo(d.key);
      const dl = normalizeGeo(d.label);
      if (norm.includes(dk) || dk.includes(norm) || norm.includes(dl) || dl.includes(norm)) {
        return d;
      }
    }
    return null;
  }

  const cityLabels = {
    istanbul: "İstanbul", ankara: "Ankara", izmir: "İzmir", bursa: "Bursa",
    antalya: "Antalya", adana: "Adana", konya: "Konya"
  };

  const isLocalIp = !clientIp || clientIp.startsWith("127.") ||
    clientIp.startsWith("::1") || clientIp.startsWith("10.0.2");

  // ipapi.co — city alanı ilçe/şehir düzeyinde (region'dan daha granüler)
  try {
    const ipParam = isLocalIp ? "" : `/${clientIp}`;
    const response = await fetch(`https://ipapi.co${ipParam}/json/`, {
      signal: AbortSignal.timeout(6000),
      headers: { "User-Agent": "NeYesem/1.0" }
    });
    if (response.ok) {
      const data = await response.json();
      const hasError = data.error === true || (typeof data.error === "string" && data.error);
      if (!hasError) {
        const rawRegion = data.region || "";
        const rawCity   = data.city   || "";
        const matched = matchCity(rawRegion) || matchCity(rawCity);
        if (matched) {
          // city alanı ilçe düzeyinde olabilir — önce city'yi dene, sonra region'ı
          const district = matchDistrict(matched, rawCity) || matchDistrict(matched, rawRegion);
          const result = {
            city: matched,
            label: cityLabels[matched] || matched.charAt(0).toUpperCase() + matched.slice(1),
            source: "ipapi.co",
            raw: rawRegion || rawCity
          };
          if (district) {
            result.district      = district.key;
            result.districtLabel = district.label;
          }
          return res.json(result);
        }
      }
    }
  } catch (_) {}

  // ipinfo.io fallback
  try {
    const ipParam = isLocalIp ? "" : `/${clientIp}`;
    const response = await fetch(`https://ipinfo.io${ipParam}/json`, {
      signal: AbortSignal.timeout(6000),
      headers: { "User-Agent": "NeYesem/1.0" }
    });
    if (response.ok) {
      const data = await response.json();
      const rawRegion = data.region || "";
      const rawCity   = data.city   || "";
      const matched = matchCity(rawRegion) || matchCity(rawCity);
      if (matched) {
        const district = matchDistrict(matched, rawCity) || matchDistrict(matched, rawRegion);
        const result = {
          city: matched,
          label: cityLabels[matched] || matched.charAt(0).toUpperCase() + matched.slice(1),
          source: "ipinfo.io",
          raw: rawRegion || rawCity
        };
        if (district) {
          result.district      = district.key;
          result.districtLabel = district.label;
        }
        return res.json(result);
      }
    }
  } catch (_) {}

  // Hiçbir servisten sonuç gelemediyse 404
  res.status(404).json({ message: "Konum tespit edilemedi." });
}));

app.get("/api/deals", (req, res) => {
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const { deals } = loadData(city === "all" ? null : city, district || null);
  const sortBy = String(req.query.sort || "").toLowerCase();
  const minPrice = parseFloat(req.query.minPrice) || 0;
  const maxPrice = parseFloat(req.query.maxPrice) || Infinity;
  let list = deals;
  if (minPrice > 0) list = list.filter((p) => p.currentPrice >= minPrice);
  if (maxPrice < Infinity) list = list.filter((p) => p.currentPrice <= maxPrice);
  if (sortBy === "price_asc") list = [...list].sort((a, b) => a.currentPrice - b.currentPrice);
  else if (sortBy === "price_desc") list = [...list].sort((a, b) => b.currentPrice - a.currentPrice);
  else if (sortBy === "discount") list = [...list].sort((a, b) => b.discountPercent - a.discountPercent);
  const limit = getLimit(req, 20, 100);
  const offset = getOffset(req);
  const total = list.length;
  const page = Number.parseInt(req.query.page, 10) || 1;
  res.json({ items: list.slice(offset, offset + limit), total, page, totalPages: Math.ceil(total / limit), limit });
});

app.get("/api/suspicious-discounts", (req, res) => {
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  const { suspiciousDiscounts } = loadData(city === "all" ? null : city, district || null);
  const sorted = suspiciousDiscounts.sort(
    (a, b) => b.discountPercent - a.discountPercent || b.currentPrice - a.currentPrice
  );
  res.json(sorted.slice(0, getLimit(req, 120, 500)));
});

app.get("/api/compare", (req, res) => {
  const query = String(req.query.query || req.query.q || "").trim();
  const city = getCityParam(req);
  const district = getDistrictParam(req);
  if (!query) {
    return res.json({ query, count: 0, bestDeal: null, suspicious: [], results: [],
      message: "Karşılaştırma için query parametresi gönderin. Örnek: /api/compare?query=tavuk&city=ankara&district=cankaya"
    });
  }
  const comparison = compareProducts(query, city === "all" ? null : city, district || null);
  const limit = getLimit(req, 80, 300);
  res.json({
    ...comparison,
    suspicious: comparison.suspicious.slice(0, limit),
    results: comparison.results.slice(0, limit)
  });
});

app.post("/api/auth/register", (req, res) => {
  const { name, email, password } = req.body || {};
  const cleanEmail = String(email || "").trim().toLowerCase();

  if (!name || !cleanEmail || !password) {
    return res.status(400).json({ message: "name, email ve password zorunlu." });
  }

  const users = readUsers();
  if (users.some((user) => String(user.email).toLowerCase() === cleanEmail)) {
    return res.status(409).json({ message: "Bu email ile kayıt var." });
  }

  const user = {
    id: `user-${Date.now()}-${crypto.randomBytes(3).toString("hex")}`,
    name: String(name).trim(),
    email: cleanEmail,
    passwordHash: hashPassword(password),
    allergies: [],
    dietPreference: "",
    calorieTarget: null,
    favoriteCategories: []
  };

  users.push(user);
  writeUsers(users);

  res.status(201).json({
    message: "Kayıt başarılı.",
    userId: user.id,
    user: publicUser(user)
  });
});

app.post("/api/auth/login", (req, res) => {
  const { email, password } = req.body || {};
  const cleanEmail = String(email || "").trim().toLowerCase();
  const users = readUsers();
  const user = users.find((item) => String(item.email).toLowerCase() === cleanEmail);

  if (!user || user.passwordHash !== hashPassword(password)) {
    return res.status(401).json({ message: "Email veya şifre hatalı." });
  }

  res.json({
    message: "Giriş başarılı.",
    userId: user.id,
    user: publicUser(user)
  });
});

app.get("/api/profile/:userId", (req, res) => {
  const users = readUsers();
  const user = users.find((item) => String(item.id) === String(req.params.userId));

  if (!user) {
    return res.status(404).json({ message: "Kullanıcı bulunamadı." });
  }

  res.json(publicUser(user));
});

app.put("/api/profile/:userId", (req, res) => {
  const users = readUsers();
  const index = users.findIndex((item) => String(item.id) === String(req.params.userId));

  if (index === -1) {
    return res.status(404).json({ message: "Kullanıcı bulunamadı." });
  }

  const body = req.body || {};
  const toStringArray = (value) => {
    if (Array.isArray(value)) {
      return value.map((item) => String(item).trim()).filter(Boolean);
    }
    return String(value || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  };

  users[index] = {
    ...users[index],
    name: body.name !== undefined ? String(body.name).trim() : users[index].name,
    allergies:
      body.allergies !== undefined ? toStringArray(body.allergies) : users[index].allergies || [],
    dietPreference:
      body.dietPreference !== undefined
        ? String(body.dietPreference || "").trim()
        : users[index].dietPreference || "",
    calorieTarget:
      body.calorieTarget !== undefined && body.calorieTarget !== ""
        ? Number(body.calorieTarget)
        : body.calorieTarget === ""
          ? null
          : users[index].calorieTarget,
    favoriteCategories:
      body.favoriteCategories !== undefined
        ? toStringArray(body.favoriteCategories)
        : users[index].favoriteCategories || []
  };

  writeUsers(users);
  res.json({
    message: "Profil güncellendi.",
    user: publicUser(users[index])
  });
});

app.use((error, req, res, next) => {
  console.error("Beklenmeyen backend hatası:", error);
  res.status(500).json({
    message: "Demo backend isteği işleyemedi.",
    detail: error.message
  });
});

ensureUsersFile();

app.listen(PORT, () => {
  console.log(`NeYesem demo backend çalışıyor: http://localhost:${PORT}`);
  if (USE_DB && dbLayer) {
    refreshDbCache();
    // 60 sn'de bir DB'den tazele (yeni scrape verisi gelirse yansır)
    setInterval(refreshDbCache, 60 * 1000);
  } else {
    // JSON modunda: startup'ta once "all" veriyi, sonra her sehiri onceden yukle
    console.log("Veri on yuklemesi basliyor...");
    setImmediate(async () => {
      try {
        const allData = loadData();
        console.log(`[1] Tum veri hazir: ${allData.products.length} urun`);

        const cities = getAvailableCities();
        let step = 2;
        for (const city of cities) {
          await new Promise((resolve) => setImmediate(resolve));
          try {
            const cityData = loadData(city);
            console.log(`[${step++}] ${city}: ${cityData.deals.length} avantajli urun`);
            // Compare cache: sehir bazinda
            for (const q of ['tavuk', 'burger', 'pizza']) {
              await new Promise((resolve) => setImmediate(resolve));
              compareProducts(q, city, null);
              await new Promise((resolve) => setImmediate(resolve));
              searchProducts(q, city, null);
            }
            // Ilce bazinda - en buyuk 3 ilceyi yukle
            const districts = getAvailableDistricts(city);
            for (const d of districts.slice(0, 3)) {
              await new Promise((resolve) => setImmediate(resolve));
              try {
                const dData = loadData(city, d.key);
                console.log(`  [ilce] ${city}/${d.key}: ${dData.deals.length} urun hazir`);
                for (const q of ['tavuk', 'burger', 'pizza', 'lahmacun', 'doner']) {
                  await new Promise((resolve) => setImmediate(resolve));
                  compareProducts(q, city, d.key);
                  await new Promise((resolve) => setImmediate(resolve));
                  searchProducts(q, city, d.key);
                }
              } catch (e) { /* ignore */ }
            }
          } catch (err) {
            console.warn(`[pre-warm] ${city} hatasi:`, err.message);
          }
        }
        console.log("Tum sehir ve ilce verileri hazir! Artik istekler aninda cevaplanacak.");
      } catch (err) {
        console.warn("On yukleme hatasi:", err.message);
      }
    });
  }
});
