from playwright.sync_api import sync_playwright
import json

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False)
    page = browser.new_page(user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
    page.goto('https://www.yemeksepeti.com/restaurant/u6sh/has-cig-kofte-dunyasi-u6sh', wait_until='domcontentloaded')
    page.wait_for_timeout(3000)
    html = page.evaluate('''() => { 
        let items = document.querySelectorAll('[data-testid="menu-product"]'); 
        let res = "";
        for(let item of items) {
            if(item.innerHTML.includes('line-through') || item.innerHTML.includes('old-price') || item.innerHTML.includes('discount')) {
                res = item.outerHTML;
                break;
            }
        }
        return res || "No discount found";
    }''')
    with open('discount_item.html', 'w', encoding='utf-8') as f:
        f.write(html)
    browser.close()
