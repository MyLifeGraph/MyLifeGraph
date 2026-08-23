#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { hostedFlutterDefines } from './write_hosted_flutter_defines.mjs';

const CLOUDFLARE = 'https://challenges.cloudflare.com';

export function webContentSecurityPolicy(environment = process.env) {
  const defines = hostedFlutterDefines(environment);
  const supabase = new URL(defines.SUPABASE_URL);
  const websocket = `wss://${supabase.host}`;
  const api = new URL(defines.AI_SERVICE_BASE_URL).origin;
  return [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "form-action 'self'",
    `script-src 'self' 'wasm-unsafe-eval' ${CLOUDFLARE}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${supabase.origin} ${CLOUDFLARE}`,
    "font-src 'self' data:",
    `connect-src 'self' ${supabase.origin} ${websocket} ${api} ${CLOUDFLARE}`,
    `frame-src ${CLOUDFLARE}`,
    "worker-src 'self' blob:",
    "manifest-src 'self'",
    "media-src 'self'",
    'upgrade-insecure-requests',
  ].join('; ');
}

export function writeWebCsp(indexPath, environment = process.env) {
  if (!indexPath) throw new Error('An index path is required.');
  const source = readFileSync(indexPath, 'utf8');
  if (source.includes('http-equiv="Content-Security-Policy"')) {
    throw new Error('index.html already contains a Content Security Policy.');
  }
  const marker = '  <meta charset="UTF-8">';
  if (!source.includes(marker)) {
    throw new Error('index.html lacks the expected charset marker.');
  }
  const policy = webContentSecurityPolicy(environment);
  const updated = source.replace(
    marker,
    `${marker}\n  <meta http-equiv="Content-Security-Policy" content="${policy}">`,
  );
  writeFileSync(indexPath, updated, { encoding: 'utf8' });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const [indexPath, ...unexpected] = process.argv.slice(2);
    if (!indexPath || unexpected.length) {
      throw new Error('Usage: node scripts/write_web_csp.mjs <index.html>');
    }
    writeWebCsp(indexPath, process.env);
    console.log('Embedded the exact hosted web CSP.');
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
