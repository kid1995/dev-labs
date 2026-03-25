#!/usr/bin/env node
/**
 * Headless browser test for DLT Frontend.
 * Checks for JS errors, page load, and visible content.
 * Usage: node scripts/test-frontend.mjs [url]
 */
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://localhost:4200';
const errors = [];
const warnings = [];
const networkErrors = [];

console.log(`\n=== Headless Browser Test: ${url} ===\n`);

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  // No cache
  bypassCSP: true,
});
const page = await context.newPage();

// Collect console errors
page.on('console', msg => {
  if (msg.type() === 'error') {
    errors.push(`[console.error] ${msg.text()}`);
  } else if (msg.type() === 'warning') {
    warnings.push(`[console.warn] ${msg.text()}`);
  }
});

// Collect page errors (uncaught exceptions)
page.on('pageerror', err => {
  errors.push(`[pageerror] ${err.message}`);
});

// Collect failed network requests
page.on('requestfailed', req => {
  networkErrors.push(`[network] ${req.method()} ${req.url()} - ${req.failure()?.errorText}`);
});

try {
  const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  const status = response?.status();
  console.log(`HTTP Status: ${status}`);

  // Wait for Angular to bootstrap
  await page.waitForTimeout(5000);

  // Check page title
  const title = await page.title();
  console.log(`Page Title: ${title}`);

  // Check if app-root exists and Angular bootstrapped
  const appRoot = await page.$('app-root');
  const appRootContent = appRoot ? await appRoot.innerHTML() : '<not found>';
  const hasContent = appRootContent.length > 50;
  console.log(`App Root Rendered: ${hasContent} (${appRootContent.length} chars)`);

  // Check if Angular router is active (may redirect to login)
  const currentUrl = page.url();
  console.log(`Current URL: ${currentUrl}`);
  const isRedirected = currentUrl !== url && currentUrl !== url + '/';
  if (isRedirected) {
    console.log(`Angular Router Active: YES (redirected to ${currentUrl})`);
  }

  // Also test /login route directly
  const loginResponse = await page.goto(`${url}/login`, { waitUntil: 'domcontentloaded', timeout: 15000 });
  await page.waitForTimeout(3000);
  console.log(`Login Route Status: ${loginResponse?.status()}`);
  const loginContent = await page.$('app-root');
  const loginHtml = loginContent ? await loginContent.innerHTML() : '';
  console.log(`Login Page Content: ${loginHtml.length > 0 ? 'YES' : 'empty'} (${loginHtml.length} chars)`);
  await page.screenshot({ path: '/tmp/dlt-frontend-login.png', fullPage: true });
  console.log(`Login Screenshot: /tmp/dlt-frontend-login.png`);

  // Check for visible text
  const bodyText = await page.textContent('body');
  console.log(`Body Text Length: ${bodyText?.trim().length || 0} chars`);
  if (bodyText?.trim()) {
    console.log(`Body Text Preview: "${bodyText.trim().substring(0, 100)}..."`);
  }

  // Take screenshot
  await page.screenshot({ path: '/tmp/dlt-frontend-test.png', fullPage: true });
  console.log(`Screenshot: /tmp/dlt-frontend-test.png`);

} catch (err) {
  errors.push(`[navigation] ${err.message}`);
}

await browser.close();

// Report
console.log(`\n--- Results ---`);
console.log(`JS Errors:      ${errors.length}`);
console.log(`Warnings:       ${warnings.length}`);
console.log(`Network Errors: ${networkErrors.length}`);

if (errors.length > 0) {
  console.log(`\n--- JS ERRORS ---`);
  errors.forEach(e => console.log(`  ${e}`));
}
if (networkErrors.length > 0) {
  console.log(`\n--- NETWORK ERRORS ---`);
  networkErrors.forEach(e => console.log(`  ${e}`));
}
if (warnings.length > 0) {
  console.log(`\n--- WARNINGS ---`);
  warnings.forEach(w => console.log(`  ${w}`));
}

const passed = errors.length === 0 && networkErrors.length === 0;
console.log(`\n=== ${passed ? 'PASS' : 'FAIL'} ===\n`);
process.exit(passed ? 0 : 1);
