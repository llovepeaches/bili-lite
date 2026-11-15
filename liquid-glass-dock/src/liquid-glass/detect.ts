import type { RenderMode } from './types';

/**
 * 兼容性分流：
 *  - Chromium 系（Chrome / Edge / Opera / Chromium）支持 backdrop-filter: url(#svgFilter)，
 *    可以真正用 feDisplacementMap 弯折「背后的内容」，走 svg 模式。
 *  - Safari / Firefox 对 backdrop-filter 的 url() 引用支持不完整，
 *    只使用函数式 backdrop-filter（blur / saturate）兜底，保证不出现空白。
 *  - 连函数式 backdrop-filter 都不支持时，组件仍保留不透明 tint 底色（见 CSS 的 @supports 兜底）。
 */
export function detectRenderMode(): RenderMode {
  if (typeof window === 'undefined' || typeof document === 'undefined') return 'fallback';

  const nav = navigator as Navigator & { userAgentData?: { brands?: Array<{ brand: string }> } };
  const ua = nav.userAgent || '';
  const brands = nav.userAgentData?.brands ?? [];
  const brandHit = brands.some((b) => /Chromium|Google Chrome|Microsoft Edge|Opera/i.test(b.brand));

  // Firefox / Safari 都不含 Chrome/Chromium 标识；Safari 含 "Safari/" 但不含 "Chrome/"
  const isFirefox = /Firefox\/|FxiOS\//i.test(ua);
  const isChromium =
    !isFirefox &&
    (brandHit || /Chrome\/\d+|Chromium\/\d+|Edg\/\d+|OPR\/\d+/i.test(ua));

  const supportsBackdrop =
    (typeof CSS !== 'undefined' &&
      (CSS.supports('backdrop-filter', 'blur(2px)') ||
        CSS.supports('-webkit-backdrop-filter', 'blur(2px)')));

  return isChromium && supportsBackdrop ? 'svg' : 'fallback';
}

/** 把任意 CSS 颜色解析成 rgb 三元组（用于按 alpha 合成 tint，不依赖 color-mix 兼容性） */
export function parseColor(input: string): [number, number, number] {
  const fallback: [number, number, number] = [191, 228, 255];
  if (!input) return fallback;
  const hex = input.trim().match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (hex) {
    let s = hex[1];
    if (s.length === 3) s = s.split('').map((c) => c + c).join('');
    return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
  }
  const rgb = input.trim().match(/rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)/i);
  if (rgb) return [Number(rgb[1]), Number(rgb[2]), Number(rgb[3])];
  // 其它写法（hsl / 命名色）：借浏览器解析
  if (typeof document !== 'undefined') {
    const el = document.createElement('span');
    el.style.color = input;
    document.body.appendChild(el);
    const computed = getComputedStyle(el).color;
    el.remove();
    const c = computed.match(/rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)/i);
    if (c) return [Number(c[1]), Number(c[2]), Number(c[3])];
  }
  return fallback;
}
