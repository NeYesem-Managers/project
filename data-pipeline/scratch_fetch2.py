from playwright.sync_api import sync_playwright
import json

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    page = browser.new_page(user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
    page.goto('https://www.yemeksepeti.com/city/bursa', wait_until='domcontentloaded')
    page.wait_for_timeout(3000)
    
    # get first 2 restaurant links
    links = page.locator('a').all()
    urls = []
    for link in links:
        href = link.get_attribute('href')
        if href and ('/restaurant/' in href or '/delivery/' in href):
            urls.append('https://www.yemeksepeti.com' + href if href.startswith('/') else href)
            if len(urls) >= 2:
                break
    
    for url in urls:
        page.goto(url, wait_until='domcontentloaded')
        page.wait_for_timeout(3000)
        items = page.locator('[data-testid="menu-product"]').all()
        for item in items:
            name = item.locator('[data-testid="menu-product-name"]').first.text_content()
            html = item.inner_html()
            # print if we find two prices or "discount" or "indirim"
            import re
            prices = re.findall(r'>([^<>]*?TL[^<>]*)<', html)
            prices = [p.strip() for p in prices if p.strip()]
            if len(prices) > 1:
                print(f"Found multiple prices for '{name}': {prices}")
                print(html[:500])
                
    browser.close()
