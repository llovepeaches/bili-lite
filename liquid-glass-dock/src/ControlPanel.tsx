import { useEffect, useMemo, useRef, useState } from 'react';
import { buildSdfPixels, paintSdfPreview } from './liquid-glass/sdf';
import type { SdfTexture } from './liquid-glass/sdf';
import { ARCHITECTURE_SNIPPET, usageSnippet } from './examples';
import type { GlassParams, RenderMode } from './liquid-glass/types';

export interface ControlPanelProps {
  params: GlassParams;
  onParams: (p: GlassParams) => void;
  mode: RenderMode;
  autoMode: boolean;
  detected: RenderMode;
  onMode: (mode: RenderMode, auto: boolean) => void;
  reducedMotion: boolean;
  onReducedMotion: (v: boolean) => void;
}

/** HSL → hex，让 tint 也能用滑块调（色相） */
function hslToHex(h: number, s: number, l: number): string {
  const sn = s / 100;
  const ln = l / 100;
  const a = sn * Math.min(ln, 1 - ln);
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    const c = ln - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
    return Math.round(255 * c).toString(16).padStart(2, '0');
  };
  return `#${f(0)}${f(8)}${f(4)}`;
}

/** 把某一通道以灰度画出，并放大与中性 128 的偏差，方便肉眼验证 R/G/B 编码 */
function paintChannel(canvas: HTMLCanvasElement | null, tex: SdfTexture, channel: number) {
  if (!canvas) return;
  canvas.width = tex.texW;
  canvas.height = tex.texH;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const img = ctx.createImageData(tex.texW, tex.texH);
  for (let i = 0; i < tex.pixels.length; i += 4) {
    const v = Math.max(0, Math.min(255, 128 + (tex.pixels[i + channel] - 128) * 2.6));
    img.data[i] = v;
    img.data[i + 1] = v;
    img.data[i + 2] = v;
    img.data[i + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
}

function Slider({
  label, value, min, max, step, unit, hint, onChange,
}: {
  label: string; value: number; min: number; max: number; step: number;
  unit: string; hint: string; onChange: (v: number) => void;
}) {
  return (
    <label className="ctrl-row">
      <span className="ctrl-row__head">
        <b>{label}</b>
        <output>{Number.isInteger(value) ? value : value.toFixed(2)}{unit}</output>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        aria-label={label}
      />
      <small>{hint}</small>
    </label>
  );
}

export function ControlPanel(props: ControlPanelProps) {
  const { params, onParams, mode, autoMode, detected, onMode, reducedMotion, onReducedMotion } = props;
  const [copied, setCopied] = useState(false);
  const [hue, setHue] = useState(205);

  // 固定尺寸的示例 SDF，用于面板里的贴图预览
  const tex = useMemo(
    () => (typeof document !== 'undefined' ? buildSdfPixels({ width: 240, height: 84, radius: 24 }) : null),
    [],
  );
  const mainRef = useRef<HTMLCanvasElement>(null);
  const rRef = useRef<HTMLCanvasElement>(null);
  const gRef = useRef<HTMLCanvasElement>(null);
  const bRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (!tex) return;
    if (mainRef.current) paintSdfPreview(mainRef.current, tex);
    paintChannel(rRef.current, tex, 0);
    paintChannel(gRef.current, tex, 1);
    paintChannel(bRef.current, tex, 2);
  }, [tex]);

  const set = <K extends keyof GlassParams>(key: K, value: GlassParams[K]) =>
    onParams({ ...params, [key]: value });

  const copyParams = async () => {
    const text = usageSnippet(params);
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  };

  return (
    <aside className="panel" aria-label="参数调试面板">
      <header className="panel__head">
        <div>
          <h2>光学参数</h2>
          <p>四个 props 实时驱动 SDF 滤镜与分层样式</p>
        </div>
        <button type="button" className={`copy-btn${copied ? ' is-copied' : ''}`} onClick={copyParams}>
          {copied ? '✓ 已复制' : '⧉ 复制当前参数'}
        </button>
      </header>

      <div className="ctrl-grid">
        <Slider
          label="distortionScale" value={params.distortionScale} min={0} max={140} step={1} unit="px"
          hint="→ feDisplacementMap 的 scale，弯折背后内容"
          onChange={(v) => set('distortionScale', v)}
        />
        <Slider
          label="blur" value={params.blur} min={0} max={36} step={1} unit="px"
          hint="→ 磨砂层 backdrop-filter: blur()"
          onChange={(v) => set('blur', v)}
        />
        <Slider
          label="tint · 色相" value={hue} min={0} max={360} step={1} unit="°"
          hint="→ 玻璃着色；右侧色块可精确取色"
          onChange={(v) => { setHue(v); set('tint', hslToHex(v, 78, 78)); }}
        />
        <Slider
          label="glow" value={params.glow} min={0} max={1} step={0.01} unit=""
          hint="→ 边缘高光 / RGB 色散 / 指针镜面高光"
          onChange={(v) => set('glow', v)}
        />
      </div>

      <div className="panel__inline">
        <label className="color-pick">
          <span>tint 精确值</span>
          <input
            type="color"
            value={params.tint}
            aria-label="tint 颜色"
            onChange={(e) => set('tint', e.target.value)}
          />
          <code>{params.tint}</code>
        </label>
        <label className="toggle">
          <input
            type="checkbox"
            checked={reducedMotion}
            onChange={(e) => onReducedMotion(e.target.checked)}
          />
          <span>强制 reduced-motion 降级</span>
        </label>
      </div>

      <div className="panel__section">
        <h3>渲染路径 <small>（自动检测：{detected === 'svg' ? 'Chromium · SVG 滤镜' : 'Safari / Firefox · backdrop-filter 兜底'}）</small></h3>
        <div className="seg" role="group" aria-label="渲染模式">
          <button type="button" className={autoMode ? 'is-on' : ''} onClick={() => onMode(detected, true)}>自动</button>
          <button type="button" className={!autoMode && mode === 'svg' ? 'is-on' : ''} onClick={() => onMode('svg', false)}>强制 SVG</button>
          <button type="button" className={!autoMode && mode === 'fallback' ? 'is-on' : ''} onClick={() => onMode('fallback', false)}>强制兜底</button>
        </div>
        <p className="panel__note">
          当前：<code>{mode}</code>。兜底模式不使用 <code>feDisplacementMap</code>，
          只靠函数式 <code>backdrop-filter</code> + tint 底色，玻璃依然可见、内容依然可点。
        </p>
      </div>

      <div className="panel__section">
        <h3>SDF 位移贴图 <small>R=X · G=Y · B=高光 · 128=中性</small></h3>
        <div className="sdf-preview">
          <figure>
            <canvas ref={mainRef} />
            <figcaption>合成贴图</figcaption>
          </figure>
          <figure><canvas ref={rRef} /><figcaption>R · X 位移</figcaption></figure>
          <figure><canvas ref={gRef} /><figcaption>G · Y 位移</figcaption></figure>
          <figure><canvas ref={bRef} /><figcaption>B · 高光</figcaption></figure>
        </div>
        <p className="panel__note">通道图已放大与 128 的偏差；轮廓处位移最强，向中心平滑衰减，正中央回到中性。</p>
      </div>

      <details className="panel__code">
        <summary>使用示例 / 分层结构</summary>
        <pre>{usageSnippet(params)}</pre>
        <pre>{ARCHITECTURE_SNIPPET}</pre>
      </details>
    </aside>
  );
}
