import { useMemo, useState } from 'react';
import { LiquidDock } from './LiquidDock';
import { FusionPlayground } from './FusionPlayground';
import { ControlPanel } from './ControlPanel';
import { GlassEnvContext } from './liquid-glass/context';
import { detectRenderMode } from './liquid-glass/detect';
import { useReducedMotion } from './liquid-glass/useReducedMotion';
import { DEFAULT_PARAMS } from './liquid-glass/types';
import type { GlassParams, RenderMode } from './liquid-glass/types';
import './liquid-glass/liquid-glass.css';
import './styles.css';

const CONTENT_CARDS = [
  { tag: 'DESIGN NOTE 01', title: '光学不是模糊', body: '沿轮廓按 SDF 法线弯折采样点，位移向中心平滑衰减，正中央回到中性 128，内容不被整体推偏。', hue: '#ff7ab6' },
  { tag: 'DESIGN NOTE 02', title: '四层互不干扰', body: '折射 / 磨砂 / 色散都是绝对定位的兄弟层，按钮位于 z4 内容层，始终锐利可点。', hue: '#7ac8ff' },
  { tag: 'DESIGN NOTE 03', title: '玻璃只用在导航', body: '列表、正文卡片保持普通材质；玻璃叠玻璃会破坏景深，这里刻意不做。', hue: '#8affd1' },
];

export default function App() {
  const [params, setParams] = useState<GlassParams>(DEFAULT_PARAMS);
  const [active, setActive] = useState('home');
  const detected = useMemo(() => detectRenderMode(), []);
  const [autoMode, setAutoMode] = useState(true);
  const [forcedMode, setForcedMode] = useState<RenderMode>('svg');
  const [forceReduced, setForceReduced] = useState(false);
  const systemReduced = useReducedMotion();

  const reducedMotion = systemReduced || forceReduced;
  const mode: RenderMode = autoMode ? detected : forcedMode;

  const handleMode = (next: RenderMode, auto: boolean) => {
    setAutoMode(auto);
    if (!auto) setForcedMode(next);
  };

  return (
    <GlassEnvContext.Provider value={{ mode, reducedMotion }}>
      <div className="page">
        <header className="page__head">
          <div className="page__eyebrow">REACT + TYPESCRIPT · INTERACTIVE SPECIMEN</div>
          <h1>Liquid Glass <em>Dock</em></h1>
          <p className="page__lead">
            用 <b>SDF 位移贴图</b>（R=X · G=Y · B=高光 · 128=中性）驱动 <code>feDisplacementMap</code> 弯折背后的内容，
            再依次叠加磨砂、边缘色散与独立的内容层。不是半透明 + blur 冒充。
          </p>
          <div className="page__chips">
            <span>distortionScale</span><span>blur</span><span>tint</span><span>glow</span>
            <i />
            <span>指针高光</span><span>按压回弹</span><span>拖拽融合</span><span>键盘可达</span>
          </div>
        </header>

        <main className="layout">
          {/* ---------------- 左：App 模拟器 + 底栏 ---------------- */}
          <section className="stage" aria-label="底栏预览">
            <div className="phone">
              {/* 高频细节背景：条纹 / 网格 / 大号字，专门用来观察折射位移 */}
              <div className="scene" aria-hidden="true">
                <div className="scene__grid" />
                <div className="scene__stripes" />
                <div className="scene__wordmark">REFRACT</div>
                <div className="scene__dots" />
              </div>

              <div className="phone__status">
                <span>9:41</span>
                <span>●●●  ▰</span>
              </div>

              <div className="phone__content">
                <p className="phone__kicker">TODAY · NOV 15</p>
                <h2>玻璃之下，<br />内容仍在流动。</h2>
                <p className="phone__sub">向下滚动看底栏如何弯折背后的条纹与文字。</p>
                <div className="card-list">
                  {CONTENT_CARDS.map((c) => (
                    <article className="content-card" key={c.tag}>
                      <span className="content-card__tag" style={{ color: c.hue }}>{c.tag}</span>
                      <h3>{c.title}</h3>
                      <p>{c.body}</p>
                    </article>
                  ))}
                </div>
                <p className="phone__tail">— 列表与正文使用普通材质，不套玻璃 —</p>
              </div>

              {/* 唯一一块玻璃：底栏 */}
              <LiquidDock
                active={active}
                onChange={setActive}
                distortionScale={params.distortionScale}
                blur={params.blur}
                tint={params.tint}
                glow={params.glow}
              />
              <div className="phone__home-indicator" aria-hidden="true" />
            </div>
            <p className="stage__caption">
              当前标签：<b>{active}</b> · 渲染路径：<b>{mode === 'svg' ? 'Chromium SVG 滤镜' : 'backdrop-filter 兜底'}</b>
              {reducedMotion ? ' · reduced-motion 已降级' : ''}
            </p>
          </section>

          {/* ---------------- 右：参数面板 + 融合实验区 ---------------- */}
          <section className="side" aria-label="调试与融合实验">
            <ControlPanel
              params={params}
              onParams={setParams}
              mode={mode}
              autoMode={autoMode}
              detected={detected}
              onMode={handleMode}
              reducedMotion={reducedMotion}
              onReducedMotion={setForceReduced}
            />
            <FusionPlayground params={params} />
          </section>
        </main>

        <footer className="page__foot">
          <h2>约束对照</h2>
          <div className="spec-table">
            <div><b>光学</b><span>canvas 逐像素生成 SDF → PNG data URL → <code>feImage</code> → <code>feDisplacementMap</code>；B 通道经 <code>feColorMatrix</code> 提亮后 screen 叠回。filter 强制 <code>sRGB</code>，否则 128 中性点会被 linearRGB 推偏。</span></div>
            <div><b>分层</b><span>z1 折射 / z2 磨砂 / z3 色散+高光 / z4 内容。前三层 <code>absolute + aria-hidden + pointer-events:none</code>，根元素无滤镜，按钮是原生 <code>&lt;button&gt;</code>。</span></div>
            <div><b>交互</b><span>rAF 节流的指针变量、<code>cubic-bezier(.22,1,.36,1)</code> 回弹、4px 阈值拖拽（不吞点击）、方向键 + Home、按距离融合形变、reduced-motion 关闭跟随与过渡。</span></div>
            <div><b>兼容</b><span>Chromium 用 <code>backdrop-filter: url(#…)</code>；Safari / Firefox 自动降级为函数式 <code>blur() saturate()</code>；两者皆不支持时 <code>@supports</code> 给实色 tint 底色，绝不空白。</span></div>
            <div><b>克制</b><span>一块玻璃只有一组光学层；列表、正文、调试面板均为普通材质；融合靠轮廓形变与高光连接带，不叠第二块玻璃。</span></div>
          </div>
        </footer>
      </div>
    </GlassEnvContext.Provider>
  );
}
