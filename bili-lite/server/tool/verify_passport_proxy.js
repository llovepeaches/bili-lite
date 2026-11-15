'use strict';

/**
 * `/api/passport/*` 代理的离线自检（不联网、不启动服务）。
 *
 * 用 Node 22 的全局 fetch 打桩，验证最容易出错的三件事：
 *   1. 上游业务码必须原样透传（-105 不能被包成 0，否则客户端看不到
 *      「需要人机验证」，会误以为登录失败原因不明）；
 *   2. 成功时把 Set-Cookie / 回调 URL 合成成 data.cookie，且不把含
 *      Cookie 的 url 整串回吐；
 *   3. 请求体按白名单过滤，RSA 密文经过标准 URL 编码。
 *
 * 运行： npm run verify:passport
 */

const assert = require('assert/strict');
const { EventEmitter } = require('events');
const passportProxy = require('../src/passport_proxy');

let mockUpstream = { code: 0, message: 'ok', data: {} };
let mockSetCookies = [];
let lastCall = null;

global.fetch = async (target, init) => {
  lastCall = { target, init };
  return {
    status: 200,
    headers: {
      getSetCookie: () => mockSetCookies,
      get: () => null,
    },
    text: async () => JSON.stringify(mockUpstream),
  };
};

function fakeReq(body, method = 'POST') {
  const req = new EventEmitter();
  req.method = method;
  process.nextTick(() => {
    if (body !== undefined) req.emit('data', Buffer.from(JSON.stringify(body)));
    req.emit('end');
  });
  return req;
}

function url(pathname, query = '') {
  return new URL(`http://localhost${pathname}${query}`);
}

async function run() {
  // --- GET /api/passport/key -----------------------------------------
  mockUpstream = {
    code: 0,
    message: 'ok',
    data: { hash: 'h-1', key: '-----BEGIN PUBLIC KEY-----\nAAA\n-----END PUBLIC KEY-----' },
  };
  let out = await passportProxy.handle(fakeReq(undefined, 'GET'), url('/api/passport/key'));
  assert.equal(out.json.code, 0);
  assert.equal(out.json.data.hash, 'h-1');
  assert.match(out.json.data.key, /BEGIN PUBLIC KEY/);
  assert.equal(lastCall.target.pathname, '/x/passport-login/web/key');
  console.log('✓ GET key 透传 hash 与 RSA 公钥，且转发到正确上游路径');

  // --- GET /api/passport/captcha -------------------------------------
  mockUpstream = {
    code: 0,
    message: 'ok',
    data: {
      type: 'geetest',
      token: 'tok-9',
      geetest: { gt: 'gt-9', challenge: 'ch-9' },
    },
  };
  out = await passportProxy.handle(fakeReq(undefined, 'GET'), url('/api/passport/captcha'));
  assert.equal(out.json.data.type, 'geetest');
  assert.equal(out.json.data.token, 'tok-9');
  assert.equal(out.json.data.geetest.gt, 'gt-9');
  assert.equal(out.json.data.geetest.challenge, 'ch-9');
  assert.equal(lastCall.target.pathname, '/x/passport-login/captcha');
  assert.equal(lastCall.target.searchParams.get('source'), 'main_web');
  assert.ok(lastCall.target.searchParams.get('t'));
  console.log('✓ GET captcha 解析极验参数并注入 source / t');

  // --- POST 上游 -105：业务码必须原样透传 ----------------------------
  mockUpstream = { code: -105, message: '验证码错误', data: {} };
  out = await passportProxy.handle(
    fakeReq({ source: 'main_web', username: 'u', password: 'BASE64+ENC==' }),
    url('/api/passport/password')
  );
  assert.equal(out.json.code, -105, '上游业务码不能被包成 0');
  assert.equal(out.json.message, '验证码错误');
  assert.equal(out.json.data.cookie, undefined, '失败时不能合成 Cookie');
  console.log('✓ POST 上游 -105 原样透传，客户端才能给出人机验证引导');

  // --- 字段白名单 + URL 编码 ----------------------------------------
  assert.ok(lastCall.init.body.includes('username=u'));
  assert.ok(!lastCall.init.body.includes('evil_field'), '白名单外字段不得转发');
  assert.ok(
    lastCall.init.body.includes('password=BASE64%2BENC%3D%3D'),
    'base64 里的 + / = 必须 URL 编码，不能直接拼接'
  );
  assert.match(lastCall.init.headers['Content-Type'], /x-www-form-urlencoded/);
  console.log('✓ 请求体按白名单过滤且 RSA 密文经过标准 URL 编码');

  // --- POST 成功：合成 Cookie，不回吐原始 url ------------------------
  mockSetCookies = ['SESSDATA=fromHeader%2Cx; Path=/'];
  mockUpstream = {
    code: 0,
    message: 'ok',
    data: {
      url: 'https://www.bilibili.com/?SESSDATA=fromUrl%2Cy&bili_jct=j9&DedeUserID=7',
    },
  };
  out = await passportProxy.handle(
    fakeReq({ source: 'main_web', username: 'u', password: 'enc' }),
    url('/api/passport/password')
  );
  assert.equal(out.json.code, 0);
  assert.equal(
    out.json.data.cookie,
    'SESSDATA=fromUrl%2Cy; bili_jct=j9; DedeUserID=7',
    '回调 URL 里的值优先，且保留百分号编码'
  );
  assert.equal(out.json.data.url, undefined, '含 Cookie 的回调 URL 不应整串回吐');
  mockSetCookies = [];
  console.log('✓ 登录成功合成 data.cookie，URL 值优先且保留 %2C 编码');

  // --- 短信发送：captcha_key 必须回传 --------------------------------
  mockUpstream = { code: 0, message: 'ok', data: { captcha_key: 'ck-42' } };
  out = await passportProxy.handle(
    fakeReq({ tel: '13800138000', cid: '86', source: 'main_web' }),
    url('/api/passport/sms/send')
  );
  assert.equal(out.json.data.captcha_key, 'ck-42');
  assert.equal(lastCall.target.pathname, '/x/passport-login/web/sms/send');
  console.log('✓ 短信发送接口回传 captcha_key');

  // --- 路由表完整性 --------------------------------------------------
  assert.equal(
    passportProxy.POST_ROUTES['/api/passport/sms/login'],
    '/x/passport-login/web/login/sms'
  );
  assert.ok(passportProxy.ALLOWED_FIELDS.includes('validate'));
  assert.ok(passportProxy.ALLOWED_FIELDS.includes('seccode'));
  console.log('✓ 三条 POST 路由与极验字段白名单齐全');

  // --- 未知路由 ------------------------------------------------------
  out = await passportProxy.handle(fakeReq(undefined, 'GET'), url('/api/passport/nope'));
  assert.equal(out.status, 404);
  console.log('✓ 未知登录接口返回 404');

  // --- 上游非 JSON（风控页）-----------------------------------------
  global.fetch = async () => ({
    status: 200,
    headers: { getSetCookie: () => [], get: () => null },
    text: async () => '<html>风控</html>',
  });
  out = await passportProxy.handle(fakeReq(undefined, 'GET'), url('/api/passport/key'));
  assert.equal(out.status, 502);
  assert.match(out.json.message, /非 JSON/);
  console.log('✓ 上游返回 HTML 风控页时降级为 502 而不是抛出未捕获异常');

  console.log('\npassport proxy 自检全部通过。');
}

run().catch((err) => {
  console.error('passport proxy 自检失败：', err);
  process.exit(1);
});
