#!/bin/sh
cd /work/JavaScript-TypeScript
node node_modules/tsx/dist/cli.mjs tests/test_vsn_caps.ts 2>&1
cd /work/JavaScript-TypeScript/tests
rm -f TestVectors 2>/dev/null
ln -s ../TestVectors TestVectors 2>/dev/null
cd ..
npx tsx tests/test_vsn_caps.ts
