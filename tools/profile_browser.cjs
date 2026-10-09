// Optional development tool: npm install --no-save --package-lock=false playwright
// Export and serve the game first, then: node tools/profile_browser.cjs [url] [label]
const { chromium } = require(process.env.SPIRITBOUND_PLAYWRIGHT || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const url = process.argv[2] || 'http://127.0.0.1:5173';
const label = (process.argv[3] || 'current').replace(/[^a-zA-Z0-9_-]/g, '-');
const outputDirectory = path.resolve(__dirname, '../artifacts');

function summarize(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return {
    frames: sorted.length,
    meanMs: sorted.reduce((a, b) => a + b, 0) / sorted.length,
    p50Ms: sorted[Math.floor(sorted.length * 0.50)],
    p95Ms: sorted[Math.floor(sorted.length * 0.95)],
    p99Ms: sorted[Math.floor(sorted.length * 0.99)],
    maxMs: sorted.at(-1),
    over60FpsBudget: sorted.filter(value => value > 16.7).length,
  };
}

(async () => {
  fs.mkdirSync(outputDirectory, { recursive: true });
  const browser = await chromium.launch({ channel: process.env.SPIRITBOUND_BROWSER_CHANNEL || 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1100, height: 760 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.addInitScript(() => {
      window.__performanceFrames = [];
      window.__performanceDraws = [];
      window.__performanceBuffers = [];
      let draws = 0;
      let buffers = 0;
      for (const method of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced', 'createBuffer']) {
        const original = WebGL2RenderingContext.prototype[method];
        WebGL2RenderingContext.prototype[method] = function (...args) {
          if (method === 'createBuffer') buffers++; else draws++;
          return original.apply(this, args);
        };
      }
      let previous;
      const frame = now => {
        if (previous !== undefined) {
          window.__performanceFrames.push(now - previous);
          window.__performanceDraws.push(draws);
          window.__performanceBuffers.push(buffers);
        }
        previous = now;
        draws = 0;
        buffers = 0;
        requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
    });
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !document.querySelector('#status'), undefined, { timeout: 90000 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(5000);
    const gpu = await page.evaluate(() => {
      const gl = document.querySelector('canvas').getContext('webgl2');
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      return {
        renderer: gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER),
        canvas: [gl.canvas.width, gl.canvas.height],
        devicePixelRatio,
        userAgent: navigator.userAgent,
      };
    });
    const sample = async scenario => {
      await page.evaluate(() => {
        window.__performanceFrames = [];
        window.__performanceDraws = [];
        window.__performanceBuffers = [];
      });
      for (const key of ['d', 'a', 'd', 'a']) {
        await page.keyboard.down(key);
        await page.waitForTimeout(1200);
        await page.keyboard.up(key);
      }
      const data = await page.evaluate(() => ({
        frames: window.__performanceFrames,
        draws: window.__performanceDraws,
        buffers: window.__performanceBuffers,
      }));
      const average = values => values.reduce((a, b) => a + b, 0) / values.length;
      return {
        scenario,
        frameTime: summarize(data.frames),
        slowFrames: data.frames.flatMap((durationMs, sampleFrame) => durationMs > 16.7 ? [{ sampleFrame, durationMs }] : []).slice(0, 20),
        averageDrawCalls: average(data.draws),
        averageNewBuffers: average(data.buffers),
      };
    };
    const results = [await sample('mouse_with_audio')];
    await page.keyboard.press('m');
    await page.keyboard.press('Home');
    await page.keyboard.press('Escape');
    results.push(await sample('mouse_muted'));
    await page.keyboard.press('Space');
    results.push(await sample('spirit_muted'));
    await page.screenshot({ path: path.join(outputDirectory, `browser-performance-${label}.png`) });
    const report = { url, gpu, results, errors };
    fs.writeFileSync(path.join(outputDirectory, `browser-performance-${label}.json`), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
    if (errors.length || results.some(result => !result.frameTime.frames)) process.exitCode = 1;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
