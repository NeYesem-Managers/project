# -*- coding: utf-8 -*-
"""
Mevcut scraped_restaurants_poc.json dosyasını yeniden sınıflandırır.
Yeniden scrape etmeye gerek kalmadan, eski veriye `urun_tipi` etiketi ekler.

Kullanım:
    python reclassify_existing.py scraped_restaurants_poc.json
"""
import json
import sys
from product_classifier import classify_product

def main(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    counts = {}
    total = 0
    for rest in data:
        for item in rest.get("menu_urunleri", []):
            tip = classify_product(
                isim=item.get("isim", ""),
                kategori=item.get("kategori", ""),
                aciklama=item.get("aciklama", ""),
            )
            item["urun_tipi"] = tip
            counts[tip] = counts.get(tip, 0) + 1
            total += 1

    out = path.replace(".json", "_classified.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"Toplam {total} ürün sınıflandırıldı -> {out}")
    for tip, n in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {tip:10}: {n}")

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "scraped_restaurants_poc.json"
    main(path)
