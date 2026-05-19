from playwright.sync_api import sync_playwright

def get_menu_html():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        page = browser.new_page(user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        page.goto('https://www.yemeksepeti.com/restaurant/v8se/burger-king-v8se', wait_until='domcontentloaded')
        page.wait_for_timeout(5000)
        html = page.evaluate('''() => { 
            let items = document.querySelectorAll('[data-testid="menu-product"]'); 
            let res = [];
            for(let item of items) {
                res.push({
                    name: item.querySelector('[data-testid="menu-product-name"]')?.textContent,
                    desc: item.querySelector('[data-testid="menu-product-description"]')?.textContent || 
                          item.querySelector('.dish-description')?.textContent || 
                          item.querySelector('.item-description')?.textContent ||
                          item.querySelector('p')?.textContent,
                    html: item.outerHTML
                });
                if(res.length >= 5) break;
            }
            return res;
        }''')
        
        for i, item in enumerate(html):
            print(f"Item {i}: {item['name']}")
            print(f"Desc: {item['desc']}")
            print("---")
            with open(f"menu_item_{i}.html", "w", encoding="utf-8") as f:
                f.write(item['html'] or '')

        browser.close()

if __name__ == '__main__':
    get_menu_html()
