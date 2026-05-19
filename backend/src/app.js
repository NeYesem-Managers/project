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
const DATA_CACHE_TTL_MS = 60 * 1000;

let dataCache = null;

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
  if (score <= 0) {
    return score;
  }

  const queryTokens = tokenizeName(query);
  const wantsMainDish = queryTokens.some((token) => MAIN_DISH_QUERY_TOKENS.has(token));
  if (!wantsMainDish) {
    return score;
  }

  const productName = normalizeName(product.productName || product.name || "");
  const queryAlreadyAsksSide = queryTokens.some((token) => SIDE_ITEM_TOKENS.includes(token));
  const looksLikeSideItem = SIDE_ITEM_TOKENS.some((token) => productName.includes(token));

  if (looksLikeSideItem && !queryAlreadyAsksSide) {
    return Math.min(score, 45);
  }

  return score;
}

function productSearchScore(product, query, options = {}) {
  const normalizedQuery = normalizeName(query);
  if (!normalizedQuery) {
    return 1;
  }

  const tokenSets = expandQueryTokenSets(query);
  if (!tokenSets.length) {
    return 0;
  }

  const name = product.productName || product.name || "";
  const category = product.category || "";
  const description = options.includeDescription === false ? "" : product.description || "";
  const restaurant = options.includeRestaurant === false ? "" : product.restaurantName || "";

  let score = 0;
  if (normalizeName(name).includes(normalizedQuery)) {
    score = 100;
  } else if (fieldMatchesTokenSets(name, tokenSets, "all")) {
    score = 95;
  } else if (fieldMatchesTokenSets(name, tokenSets, "any")) {
    score = 80;
  } else if (fieldMatchesTokenSets(category, tokenSets, "all")) {
    score = 65;
  } else if (fieldMatchesTokenSets(category, tokenSets, "any")) {
    score = 55;
  } else if (fieldMatchesTokenSets(description, tokenSets, "all")) {
    score = 35;
  } else if (fieldMatchesTokenSets(restaurant, tokenSets, "all")) {
    score = 25;
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

function normalizeGetirOutput() {
  const files = findJsonFiles(getirOutputPath);
  const restaurants = [];
  const products = [];

  files.forEach((filePath, fileIndex) => {
    const restaurant = readJsonFile(filePath, null);
    if (!restaurant || typeof restaurant !== "object" || Array.isArray(restaurant)) {
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

function loadData() {
  const now = Date.now();
  if (dataCache && now - dataCache.loadedAt < DATA_CACHE_TTL_MS) {
    return dataCache.data;
  }

  const yemeksepetiData = readJsonFile(restaurantsPath, []);
  const yemeksepeti = normalizeYemeksepetiRestaurants(yemeksepetiData);
  const getir = normalizeGetirOutput();

  const products = analyzeProducts([...yemeksepeti.products, ...getir.products]).map(stripInternalFields);
  const restaurants = [...yemeksepeti.restaurants, ...getir.restaurants];
  const suspiciousDiscounts = products.filter((product) => product.isSuspiciousDiscount);
  const deals = products
    .filter((product) => product.currentPrice !== null && product.currentPrice > 0)
    .filter((product) => !product.isSuspiciousDiscount)
    .filter((product) => product.dealScore > 0 || product.discountPercent >= 5)
    .sort((a, b) => b.dealScore - a.dealScore || a.currentPrice - b.currentPrice);

  const sources = ["Yemeksepeti scraper JSON"];
  if (getir.fileCount > 0 && getir.products.length > 0) {
    sources.push("Getir scraper output");
  }

  const data = {
    restaurants,
    products,
    suspiciousDiscounts,
    deals,
    sources,
    getirFileCount: getir.fileCount
  };

  dataCache = { loadedAt: now, data };
  return data;
}

function getLimit(req, defaultLimit, maxLimit) {
  const rawLimit = Number.parseInt(req.query.limit, 10);
  if (!Number.isFinite(rawLimit) || rawLimit <= 0) {
    return defaultLimit;
  }
  return Math.min(rawLimit, maxLimit);
}

function queryMatchesProduct(product, query, options = {}) {
  return productSearchScore(product, query, options) > 0;
}

function compareProducts(query) {
  const { products } = loadData();
  const scoredProducts = products
    .filter((product) => product.currentPrice !== null && product.currentPrice > 0)
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

  return {
    query,
    count: results.length,
    bestDeal: results[0] || null,
    suspicious: results.filter((product) => product.compareSuspicious || product.isSuspiciousDiscount),
    results
  };
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
      "/api/restaurants",
      "/api/products",
      "/api/products/:id",
      "/api/products/:id/analysis",
      "/api/search?q=burger",
      "/api/recommendations",
      "/api/deals",
      "/api/suspicious-discounts",
      "/api/compare?query=tavuk",
      "/api/auth/register",
      "/api/auth/login",
      "/api/profile/:userId"
    ]
  });
});

app.get("/api/health", (req, res) => {
  const { restaurants, products, suspiciousDiscounts, deals, sources } = loadData();
  const users = readUsers();

  res.json({
    status: "ok",
    sources,
    restaurantCount: restaurants.length,
    productCount: products.length,
    suspiciousDiscountCount: suspiciousDiscounts.length,
    dealCount: deals.length,
    userCount: users.length
  });
});

app.get("/api/restaurants", (req, res) => {
  const { restaurants } = loadData();
  res.json(restaurants.slice(0, getLimit(req, 50, 500)));
});

app.get("/api/products", (req, res) => {
  const { products } = loadData();
  res.json(products.slice(0, getLimit(req, 200, 1000)));
});

app.get("/api/products/:id", (req, res) => {
  const { products } = loadData();
  const product = products.find((item) => String(item.id) === String(req.params.id));

  if (!product) {
    return res.status(404).json({ message: "Ürün bulunamadı" });
  }

  res.json(product);
});

app.get("/api/products/:id/analysis", (req, res) => {
  const { products } = loadData();
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

app.get("/api/search", (req, res) => {
  const q = req.query.q || "";
  const { products } = loadData();
  const filtered = products.filter((product) => queryMatchesProduct(product, q));
  res.json(filtered.slice(0, getLimit(req, 50, 300)));
});

app.get("/api/recommendations", (req, res) => {
  const { deals, products } = loadData();
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

app.get("/api/deals", (req, res) => {
  const { deals } = loadData();
  res.json(deals.slice(0, getLimit(req, 80, 300)));
});

app.get("/api/suspicious-discounts", (req, res) => {
  const { suspiciousDiscounts } = loadData();
  const sorted = suspiciousDiscounts.sort(
    (a, b) => b.discountPercent - a.discountPercent || b.currentPrice - a.currentPrice
  );
  res.json(sorted.slice(0, getLimit(req, 120, 500)));
});

app.get("/api/compare", (req, res) => {
  const query = String(req.query.query || req.query.q || "").trim();
  if (!query) {
    return res.json({
      query,
      count: 0,
      bestDeal: null,
      suspicious: [],
      results: [],
      message: "Karşılaştırma için query parametresi gönderin. Örnek: /api/compare?query=tavuk"
    });
  }

  const comparison = compareProducts(query);
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
});
