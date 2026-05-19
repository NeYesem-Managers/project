from playwright.sync_api import sync_playwright
from playwright_stealth import Stealth
import time

with sync_playwright() as p:
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    browser = p.chromium.launch(headless=False, args=["--disable-blink-features=AutomationControlled"])
    context = browser.new_context(user_agent=USER_AGENT, viewport={'width': 1920, 'height': 1080})
    page = context.new_page()
    stealth = Stealth()
    stealth.apply_stealth_sync(page)
    
    url = "https://www.yemeksepeti.com/restaurant/skov/jets-burger-skov"
    page.goto(url, wait_until="domcontentloaded", timeout=60000)
    time.sleep(5)
    
    # Let's find any element containing /5
    print("Finding rating:")
    elements = page.locator('span, p, div').all()
    for el in elements:
        try:
            txt = el.text_content()
            if txt and "/5" in txt and len(txt) < 15:
                print("Found rating element HTML:")
                print(el.evaluate("node => node.outerHTML"))
                break
        except:
            pass
            
    browser.close()
