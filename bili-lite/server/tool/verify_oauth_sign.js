'use strict';

/**
 * 官方签名 2.0 算法自检
 * ------------------------------------------------------------------
 * 用 B 站官方公开的鉴权样例（www.bilibili.com/read/cv16173511/）作为测试向量，
 * 验证 canonical string 拼接顺序与 HMAC-SHA256 结果完全一致。
 * 样例是 1.0 版公共头；2.0 版仅把 x-bili-signature-version 换成 2.0，
 * 并额外要求 access-token 头（不参与签名串），拼接规则相同。
 */

const crypto = require('crypto');
const { signCanonical, buildCanonical } = require('../src/oauth');

let passed = 0;
let failed = 0;

function check(name, actual, expected) {
  const ok = actual === expected;
  if (ok) passed += 1;
  else failed += 1;
  console.log(`${ok ? '  ✓' : '  ✗'} ${name}`);
  if (!ok) {
    console.log(`      actual  : ${actual}`);
    console.log(`      expected: ${expected}`);
  }
}

console.log('\n官方签名 2.0 · 算法自检');
console.log('──────────────────────────────────────────────');

// 1. 官方公开样例（1.0）的 HMAC 结果
const sig = signCanonical(
  'k5imtTt9JOI8o3ifp1bbbfIYOXP1iC', // AccessKeySecret
  'z7T4ELf1gbFbGAlKw1s4UCvi', // x-bili-accesskeyid
  '5b05fb5bc7307c2e23235462ff2d6d6e', // x-bili-content-md5
  '8832905', // x-bili-signature-nonce
  '1650151456', // x-bili-timestamp
  '1.0'
);
check(
  'HMAC-SHA256 与官方样例一致',
  sig,
  '0f0aed7b7e0a7b1283a2318805b0b05a4ef2918feb60828575ed2e554be0eccd'
);

// 2. canonical 的 6 行顺序、分隔符、无尾随换行
const canonical = buildCanonical({
  accessKeyId: 'cid',
  contentMd5: 'md5',
  nonce: 'nonce',
  timestamp: '1700000000',
});
check(
  'canonical 按 ASCII 字典序、\\n 连接、无尾随换行',
  canonical,
  [
    'x-bili-accesskeyid:cid',
    'x-bili-content-md5:md5',
    'x-bili-signature-method:HMAC-SHA256',
    'x-bili-signature-nonce:nonce',
    'x-bili-signature-version:2.0',
    'x-bili-timestamp:1700000000',
  ].join('\n')
);
check('canonical 末字符不是换行', canonical.endsWith('\n'), false);

// 3. 空 body / GET 的 content-md5（官方文档明确要求）
check(
  '空请求体 MD5 = d41d8cd98f00b204e9800998ecf8427e',
  crypto.createHash('md5').update('').digest('hex'),
  'd41d8cd98f00b204e9800998ecf8427e'
);

// 4. 2.0 版签名串里不含 access-token / Authorization / host
check('签名串不含 access-token', canonical.includes('access-token'), false);
check('签名串不含 Authorization', canonical.includes('Authorization'), false);
check('签名串不含 host', canonical.includes('host:'), false);

console.log('──────────────────────────────────────────────');
console.log(`结果：${passed} 通过 / ${failed} 失败\n`);
process.exit(failed ? 1 : 0);
