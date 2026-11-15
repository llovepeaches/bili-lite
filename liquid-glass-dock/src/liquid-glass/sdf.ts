/**
 * SDF 位移贴图生成器
 * ---------------------------------------------------------------------------
 * 通道约定（严格按需求）：
 *   R = X 方向位移，G = Y 方向位移，B = 镜面高光，128 = 中性
 *   A = 255（不透明，避免 premultiplied alpha 污染通道值）
 *
 * feDisplacementMap 的采样规则：
 *   sampleXY = P + scale * (channel - 0.5)
 * 因此 128/255 ≈ 0.502 近似零位移；R/G 越偏离 128，位移越强。
 * distortionScale 直接映射到 filter 的 scale 属性，贴图本身只编码「方向 + 剖面」。
 *
 * 关键：filter 必须声明 color-interpolation-filters="sRGB"。
 * 默认的 linearRGB 会把 0.5 的通道值换算成 sRGB 0.735，中性点会被整体推偏。
 */

export interface SdfOptions {
  /** 玻璃的物理宽高（CSS px） */
  width: number;
  height: number;
  /** 圆角半径（CSS px） */
  radius: number;
  /** 折射带厚度，占「轮廓 → 中心」距离（半短边）的比例；中心位移恒为 0 */
  bandRatio?: number;
}

export interface SdfTexture {
  url: string;
  /** 贴图像素尺寸（与物理尺寸成比例，feImage 会拉伸回元素尺寸） */
  texW: number;
  texH: number;
  pixels: Uint8ClampedArray;
}

const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);

/** 圆角矩形有符号距离场：d < 0 在内部，d > 0 在外部 */
export function sdRoundRect(x: number, y: number, w: number, h: number, r: number): number {
  const rad = Math.min(r, w / 2, h / 2);
  const qx = Math.abs(x - w / 2) - (w / 2 - rad);
  const qy = Math.abs(y - h / 2) - (h / 2 - rad);
  const outside = Math.hypot(Math.max(qx, 0), Math.max(qy, 0));
  const inside = Math.min(Math.max(qx, qy), 0);
  return outside + inside - rad;
}

/**
 * 生成归一化到 [0,1] 的位移贴图。
 * 视觉模型：把玻璃看成一个有厚度的凸透镜，位移沿「轮廓 → 中心」平滑衰减，
 * 轮廓处最强、正中央归零（128 中性），中央内容因此保持原位、不被整体推偏。
 */
export function buildSdfPixels(opts: SdfOptions): SdfTexture {
  const { width: w, height: h, radius, bandRatio = 0.85 } = opts;
  const safeW = Math.max(1, w);
  const safeH = Math.max(1, h);
  // 贴图分辨率：够表达平滑剖面即可，避免 data URL 过大
  const texW = clamp(Math.round(safeW / 2), 96, 384);
  const texH = clamp(Math.round(safeH / 2), 96, 384);
  // 圆角矩形中心的 SDF 值恒为 -min(w,h)/2，所以用「半短边」归一化：
  // 中心 t→1 → 剖面→0 → 128 中性；轮廓 t→0 → 位移最强。
  const band = Math.max(6, (Math.min(safeW, safeH) / 2) * bandRatio);

  const pixels = new Uint8ClampedArray(texW * texH * 4);
  // 光源在左上；法线朝左上的轮廓会亮，形成镜面高光带
  const lx = -0.56;
  const ly = -0.83;

  for (let py = 0; py < texH; py++) {
    // 贴图像素 → 物理坐标
    const y = ((py + 0.5) / texH) * safeH;
    for (let px = 0; px < texW; px++) {
      const x = ((px + 0.5) / texW) * safeW;
      const d = sdRoundRect(x, y, safeW, safeH, radius);

      // 数值梯度 = 指向外部的单位法线
      const eps = 1;
      const gx = sdRoundRect(x + eps, y, safeW, safeH, radius) - sdRoundRect(x - eps, y, safeW, safeH, radius);
      const gy = sdRoundRect(x, y + eps, safeW, safeH, radius) - sdRoundRect(x, y - eps, safeW, safeH, radius);
      const glen = Math.hypot(gx, gy) || 1;
      const nx = gx / glen;
      const ny = gy / glen;

      // t: 0 = 恰好在轮廓，1 = 进入透镜中央；带外位移归零
      const t = clamp(-d / band, 0, 1);
      // 平缓剖面 = 大尺度形变：即使后面还有一层 blur()，弯折也不会被完全抹平
      const profile = Math.pow(1 - t, 0.85);
      // 轮廓外侧留一小段过渡，避免硬边
      const outer = d > 0 ? Math.exp(-d / (band * 0.12)) * 0.35 : 0;
      const amp = clamp(profile + outer, 0, 1);

      // 向中心采样（-法线）→ 边缘内容向外扩张，形成凸透镜放大感
      const dx = -nx * amp;
      const dy = -ny * amp;

      const facing = clamp(nx * lx + ny * ly, 0, 1);
      const spec = facing * Math.pow(1 - t, 2.1) * 1.0;

      const i = (py * texW + px) * 4;
      pixels[i] = clamp(128 + dx * 127, 0, 255);       // R → X 位移
      pixels[i + 1] = clamp(128 + dy * 127, 0, 255);   // G → Y 位移
      pixels[i + 2] = clamp(128 + spec * 118, 0, 255); // B → 高光（始终 ≥ 中性）
      pixels[i + 3] = 255;
    }
  }

  const url = pixelsToDataUrl(pixels, texW, texH);
  return { url, texW, texH, pixels };
}

/** 把像素数组编码成 PNG data URL（不依赖任何第三方库） */
export function pixelsToDataUrl(pixels: Uint8ClampedArray, w: number, h: number): string {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) return '';
  const img = ctx.createImageData(w, h);
  img.data.set(pixels);
  ctx.putImageData(img, 0, 0);
  return canvas.toDataURL('image/png');
}

/** 调试面板用：把当前贴图直接画进一个 canvas，证明 SDF 是真实生成的 */
export function paintSdfPreview(canvas: HTMLCanvasElement, tex: SdfTexture): void {
  canvas.width = tex.texW;
  canvas.height = tex.texH;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const img = ctx.createImageData(tex.texW, tex.texH);
  img.data.set(tex.pixels);
  ctx.putImageData(img, 0, 0);
}
