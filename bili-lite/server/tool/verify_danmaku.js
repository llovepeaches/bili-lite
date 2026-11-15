/**
 * 弹幕 XML 实体解码自检。
 *
 * 背景：B 站 `x/v1/dm/list.so` 的 `<d>` 文本节点里同时存在十进制数字实体、
 * 十六进制数字实体和 HTML 命名实体。旧版 decodeXml 用 String.fromCharCode
 * 解十进制实体，emoji 会变成私用区乱码；十六进制与 &nbsp; 则完全没解，
 * 用户会看到「&#x1F602;」这样的字面量。这里把回归点固定下来。
 *
 * 纯离线：不发起任何网络请求，直接调用 normalize.js 的纯函数。
 */
'use strict';

const assert = require('node:assert/strict');
const { parseDanmakuXml } = require('../src/normalize');

let passed = 0;
function check(name, fn) {
  fn();
  passed += 1;
  console.log(`✓ ${name}`);
}

/** 把若干段弹幕文本塞进 `<d>` 节点，返回解析后的文字数组。 */
function texts(...bodies) {
  const xml = bodies
    .map((b, i) => `<d p="${i + 1},1,25,16777215,0,0,0,0">${b}</d>`)
    .join('');
  return parseDanmakuXml(xml).map((d) => d.text);
}

check('十进制 BMP 外码点解成完整 emoji，而不是私用区乱码', () => {
  assert.equal(texts('表情 &#128512;')[0], '表情 😀');
});

check('BMP 内的十进制实体仍然正确', () => {
  assert.equal(texts('A &#65; B')[0], 'A A B');
});

check('十六进制数字实体 &#x1F602; 被解码', () => {
  assert.equal(texts('笑 &#x1F602;')[0], '笑 😂');
});

check('十六进制大小写不敏感', () => {
  assert.equal(texts('&#x1f600;')[0], '😀');
});

check('HTML 命名实体 &nbsp; 还原为空格', () => {
  assert.equal(texts('前排&nbsp;签到')[0], '前排 签到');
});

check('&lt; &gt; &quot; &apos; 四个基础实体仍正确', () => {
  assert.equal(
    texts('&lt;b&gt;加粗&lt;/b&gt; &quot;ok&quot; &apos;yes&apos;')[0],
    '<b>加粗</b> "ok" \'yes\''
  );
});

check('&amp; 最后解，&amp;lt; 只解一次，不把字面量二次解码成 <', () => {
  assert.equal(texts('&amp;lt; 不是标签')[0], '&lt; 不是标签');
});

check('&amp;#128512; 保留为字面量，不伪装成 emoji', () => {
  assert.equal(texts('&amp;#128512;')[0], '&#128512;');
});

check('越界 / 非法码点不抛异常，也不污染整条弹幕', () => {
  assert.equal(texts('好 &#99999999; 文 &#xD800;')[0], '好  文 ');
});

check('普通中文与换行原样保留，p 属性解析不受影响', () => {
  const xml = '<d p="12.5,4,25,16711680,0,0,0,0">第一行\n第二行</d>';
  const list = parseDanmakuXml(xml);
  assert.equal(list.length, 1);
  assert.equal(list[0].text, '第一行\n第二行');
  assert.equal(list[0].time, 12500);
  assert.equal(list[0].mode, 4);
  assert.equal(list[0].color, 16711680);
});

console.log(`\n弹幕实体解码自检全部通过（${passed} 项）。`);
