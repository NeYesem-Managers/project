# -*- coding: utf-8 -*-
"""
Ürün Tipi Sınıflandırıcı (Product Type Classifier)
===================================================
Bir menü ürününü "yemek" (food), "sos" (sauce), "icecek" (drink) veya
"ekstra" (extra/side) olarak etiketler.

Sorun: Scraper tüm menü kartlarını tek düz listeye atıyordu; soslar, içecekler
ve ekstralar gerçek yemeklerle aynı yerde listeleniyordu. Bu modül hem scraper
hem de backend tarafından ortak kullanılabilecek tutarlı bir etiketleme sağlar.

Kullanım:
    from product_classifier import classify_product
    tip = classify_product(isim="Acı Sos", kategori="Soslar")  # -> "sos"
"""

import re
import unicodedata

# Kategori adından doğrudan çıkarılabilen güçlü sinyaller (önce buna bakılır)
CATEGORY_HINTS = {
    "sos": ["sos", "sauce"],
    "icecek": [
        "icecek", "icecekler", "drink", "beverage", "mesrubat", "kola", "ayran",
        "soda", "su ", "sular", "kahve", "cay", "tea", "coffee", "smoothie",
        "milkshake", "limonata", "shake",
    ],
    "ekstra": [
        "ekstra", "extra", "yan urun", "ek malzeme", "soslar ve ekstralar",
        "tamamlayici", "ilave", "addon", "add-on", "ek lezzet", "garnitur",
    ],
    "tatli": ["tatli", "dessert", "tatlilar"],
}

# Ürün adında geçen yan ürün/sos token'ları (kategori yoksa veya zayıfsa)
# DİKKAT: "soslu" (sauce-topped) bir YEMEK'tir, sos'un kendisi değil.
SIDE_NAME_TOKENS = [
    "ketcap", "mayonez", "hardal", "ranch sos", "barbeku sos", "bbq sos",
    "sarimsakli sos", "acika", "nar eksisi", "nar eksili sos", "cig sos",
]
DRINK_NAME_TOKENS = [
    "ayran", "kola", "cola", "fanta", "sprite", "soda", "sumeker", "salgam",
    "limonata", "ice tea", "icetea", "kahve", "latte", "espresso",
    "smoothie", "milkshake", "shake", "meyve suyu", "gazoz", "mesrubat",
    "americano", "cappuccino", "mocha", "fuse tea", "fusetea", "churchill",
    "su 0", "su 50", "damla su", "pinar su", "erikli",
]
EXTRA_NAME_TOKENS = [
    "ekstra", "ilave porsiyon", "patates kizartmasi", "lavas", "baharat",
    "tursu", "garnitur", "yan urun", "tasima cantasi", "porsiyon ek",
]


def _normalize(text):
    if not text:
        return ""
    text = str(text).lower().strip()
    # Türkçe karakterleri sadeleştir (eşleştirme için)
    replacements = {
        "ı": "i", "ş": "s", "ğ": "g", "ü": "u", "ö": "o", "ç": "c", "â": "a",
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"\s+", " ", text)
    return text


def _matches_any(haystack, tokens):
    return any(token in haystack for token in tokens)


def _matches_word(haystack, tokens):
    """
    Token'ı TAM KELİME olarak arar (word boundary). Böylece 'ketcap' -> 'Acı Ketçap'
    eşleşir ama 'Ketçaplı Tavuk Dürüm' (ketcapli) eşleşmez; -li/-lu eki 'X'li yemek'
    anlamına gelir ve sosun kendisi değildir.
    """
    return any(re.search(r"\b" + re.escape(token) + r"\b", haystack) for token in tokens)


def classify_product(isim="", kategori="", aciklama=""):
    """
    Bir ürünü sınıflandırır.

    Dönüş değerleri: "yemek", "sos", "icecek", "ekstra", "tatli"

    Öncelik sırası:
      1. Kategori adındaki güçlü sinyaller
      2. Ürün adındaki token'lar
      3. Varsayılan: "yemek"
    """
    cat = _normalize(kategori)
    name = _normalize(isim)

    # 1) Kategori adından kesin sınıflandırma
    if cat:
        for tip, hints in CATEGORY_HINTS.items():
            if _matches_any(cat, hints):
                return tip

    # 2) Ürün adından sınıflandırma (kategori yoksa veya "yemek"e işaret ediyorsa)
    #    Parantez içi ve boyut/miktar eklerini ("(250 ml)", "1 kg.", "3 adet")
    #    temizleyip çekirdek ad üzerinden değerlendiririz; aksi halde
    #    "Nar Ekşisi (250 ml)" gibi ürünler kelime sayısı yüzünden kaçar.
    name_core = re.sub(r"\(.*?\)", " ", name)
    name_core = re.sub(
        r"\b\d+([.,]\d+)?\s*(gr|gram|g|kg|ml|cl|lt|l|adet|porsiyon|li|lu|x)\b",
        " ", name_core,
    )
    name_core = re.sub(r"\s+", " ", name_core).strip()

    # İçecek: ad içinde içecek token'ı (tam kelime) geçiyorsa VE kısa bir adsa
    drink_hit = _matches_word(name_core, DRINK_NAME_TOKENS)
    # "cikolata" içindeki "kola" gibi yanlış eşleşmeleri ele
    false_drink = "cikolata" in name_core or "kolay" in name_core
    if drink_hit and not false_drink and len(name_core) <= 35:
        return "icecek"
    # Sadece adı tam "sos" / "... sosu" / "... sos" olan KISA ürünler sostur.
    # "soslu spaghetti", "ketçaplı tavuk" gibi yemekler hariç tutulur.
    is_short = len(name_core.split()) <= 3
    looks_like_sauce = (
        name_core == "sos"
        or name_core.endswith(" sos")
        or name_core.endswith(" sosu")
        or _matches_word(name_core, SIDE_NAME_TOKENS)
    )
    if looks_like_sauce and "soslu" not in name_core and is_short:
        return "sos"
    if _matches_word(name_core, EXTRA_NAME_TOKENS) and len(name_core) <= 30:
        return "ekstra"

    # 3) Varsayılan: gerçek yemek
    return "yemek"


def is_main_food(isim="", kategori="", aciklama=""):
    """Ürün gerçek bir yemek mi? (sos/içecek/ekstra değil)"""
    return classify_product(isim, kategori, aciklama) == "yemek"


if __name__ == "__main__":
    # Hızlı test
    tests = [
        ("Acı Sos", "Soslar"),
        ("Adana Dürüm", "Dürümler"),
        ("Ayran", "İçecekler"),
        ("Sade Pestil (250 gr.)", ""),
        ("Patates Kızartması", "Yan Ürünler"),
        ("Sarımsaklı Sos", ""),
        ("Coca Cola 330ml", ""),
        ("Cheeseburger Menü", "Burgerler"),
    ]
    for isim, kat in tests:
        print(f"{isim!r:35} | kat={kat!r:15} -> {classify_product(isim, kat)}")
