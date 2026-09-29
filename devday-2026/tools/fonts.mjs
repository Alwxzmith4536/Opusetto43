// Headless Chromium here does not trust the sandbox's HTTPS proxy CA, so Google Fonts
// requests are fetched with curl (which does) and handed back to the page.
import { execFileSync } from 'child_process';
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36';
const cache = new Map();
export async function routeFonts(page) {
  await page.route(/fonts\.(googleapis|gstatic)\.com/, async route => {
    const url = route.request().url();
    try {
      if (!cache.has(url)) cache.set(url, execFileSync('curl', ['-sSfL', '-A', UA, url], { maxBuffer: 64 << 20 }));
      const css = url.includes('googleapis');
      await route.fulfill({ status: 200, body: cache.get(url), headers: { 'content-type': css ? 'text/css' : 'font/woff2', 'access-control-allow-origin': '*' } });
    } catch (e) { await route.abort(); }
  });
}
