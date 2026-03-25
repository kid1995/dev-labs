#!/usr/bin/env node
import { chromium } from 'playwright';

const url = 'http://localhost:4200';
const errors = [];
const navigations = [];

console.log(`\n=== Login Button Test ===\n`);

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();

page.on('console', msg => {
  const text = msg.text().substring(0, 300);
  if (msg.type() === 'error') {
    errors.push(`[console.error] ${text}`);
    console.log(`  ERROR: ${text}`);
  }
});
page.on('pageerror', err => {
  errors.push(`[pageerror] ${err.message}`);
  console.log(`  PAGEERROR: ${err.message.substring(0, 200)}`);
});
page.on('request', req => {
  if (req.url().includes('openid') || req.url().includes('auth') || req.url().includes('keycloak') || req.url().includes('8180')) {
    navigations.push(`${req.method()} ${req.url()}`);
    console.log(`  REQUEST: ${req.method()} ${req.url()}`);
  }
});
page.on('requestfailed', req => {
  console.log(`  FAILED: ${req.method()} ${req.url()} → ${req.failure()?.errorText}`);
});

// Navigate
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
await page.waitForTimeout(4000);
console.log(`Page loaded: ${page.url()}`);

// Click the span inside si-button (shadow DOM may block direct click)
try {
  // Try clicking the span text directly
  const ssoText = await page.getByText('Login with SSO');
  if (ssoText) {
    console.log(`\nClicking "Login with SSO"...`);
    await ssoText.click({ timeout: 5000 });
    await page.waitForTimeout(5000);
    console.log(`After click URL: ${page.url()}`);
  }
} catch (e) {
  console.log(`Click failed: ${e.message.substring(0, 200)}`);
  // Fallback: evaluate click in page context
  console.log(`Trying JS click...`);
  await page.evaluate(() => {
    const btn = document.querySelector('si-button');
    if (btn) btn.click();
  });
  await page.waitForTimeout(5000);
  console.log(`After JS click URL: ${page.url()}`);
}

await page.screenshot({ path: '/tmp/dlt-login-click.png', fullPage: true });

await browser.close();

console.log(`\n--- Auth Requests: ${navigations.length} ---`);
navigations.forEach(n => console.log(`  ${n}`));
console.log(`--- Errors: ${errors.length} ---`);
errors.forEach(e => console.log(`  ${e}`));
console.log(`\n=== ${errors.length === 0 && navigations.length > 0 ? 'PASS' : 'NEEDS FIX'} ===\n`);
