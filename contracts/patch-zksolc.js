/**
 * Patches @matterlabs/hardhat-zksync-solc utils.js to work with undici v6.
 * undici v6 removed the `maxRedirections` option from request() — use interceptors instead.
 *
 * Run once after npm install:  node patch-zksolc.js
 */

const fs = require('fs');
const path = require('path');

const utilsPath = path.join(
  __dirname,
  'node_modules',
  '@matterlabs',
  'hardhat-zksync-solc',
  'dist',
  'src',
  'utils.js'
);

if (!fs.existsSync(utilsPath)) {
  console.error('ERROR: utils.js not found at', utilsPath);
  process.exit(1);
}

let src = fs.readFileSync(utilsPath, 'utf8');

// Already patched?
if (src.includes('/* patched-redirect */')) {
  console.log('Already patched — nothing to do.');
  process.exit(0);
}

// ── Patch 1: download() — replace maxRedirections: 10 with redirect interceptor ──
// Original block:
//   const dispatcher = getGlobalDispatcher();
//   const response = await request(url, {
//       dispatcher,
//       headersTimeout: timeoutMillis,
//       maxRedirections: 10,
//       ...
//   });
src = src.replace(
  /const dispatcher = getGlobalDispatcher\(\);\s*\/\/ Fetch the url\s*const response = await request\(url, \{\s*dispatcher,\s*headersTimeout: timeoutMillis,\s*maxRedirections: 10,/,
  `/* patched-redirect */
    const { Agent, interceptors: _interceptors } = await Promise.resolve().then(() => __importStar(require('undici')));
    const _redirectAgent = new Agent().compose(_interceptors.redirect({ maxRedirections: 10 }));
    // Fetch the url
    const response = await request(url, {
        dispatcher: _redirectAgent,
        headersTimeout: timeoutMillis,`
);

// ── Patch 2: getLatestRelease() — remove maxRedirections: 0 (undici v6 default = no redirect) ──
src = src.replace(
  /const response = await request\(url, \{\s*headersTimeout: timeout,\s*maxRedirections: 0,/,
  `const response = await request(url, {
            headersTimeout: timeout,`
);

fs.writeFileSync(utilsPath, src, 'utf8');
console.log('✅ Patched successfully:', utilsPath);
