import { useEffect, useId, useMemo, useState } from 'react';
import type { CSSProperties, KeyboardEvent, MutableRefObject } from 'react';
import { RefractionFilter } from './RefractionFilter';
import { buildSdfPixels } from './sdf';
import { parseColor } from './detect';
import { useGlassEnv } from './context';
import { useGlassInteractions } from './useGlassInteractions';
import { DEFAULT_PARAMS } from './types';
import type { LiquidGlassProps } from './types';

/**
 * LiquidGlass —— 四层严格分离的液态玻璃容器
 *
 *   ┌─────────────────────────────────────────────────┐
 *   │ z4 内容层   .lg__content    ← 兄弟节点，无滤镜    │  文字 / 按钮清晰可点
 *   │ z3 边缘层   .lg__edge       ← RGB 色散 + 指针高光 │
 *   │ z2 磨砂层   .lg__frost      ← backdrop-filter     │
 *   │ z1 折射层   .lg__refraction ← backdrop-filter:url │  Chromium 专属
 *   └─────────────────────────────────────────────────┘
 *
 * 根元素 .lg 本身**不施加任何 filter / backdrop-filter / opacity**，
 * 所以内容层永远不会被弯折或模糊。所有光学层都是 aria-hidden + pointer-events:none。
 *
 * 「玻璃叠玻璃」不会发生：一个 LiquidGlass 实例只有一组光学层；
 * 底栏与浮动 chip 是彼此独立的实例，靠近时靠 --lg-merge 形变而非再叠一块玻璃。
 */
export function LiquidGlass(props: LiquidGlassProps) {
  const {
    children,
    distortionScale = DEFAULT_PARAMS.distortionScale,
    blur = DEFAULT_PARAMS.blur,
    tint = DEFAULT_PARAMS.tint,
    glow = DEFAULT_PARAMS.glow,
    radius = 28,
    draggable = false,
    onPositionChange,
    mode: modeProp,
    merge = 0,
    className = '',
    style,
    contentStyle,
    ariaLabel,
    onActivate,
    elementRef,
    ...rest
  } = props;

  const env = useGlassEnv();
  const mode = modeProp ?? env.mode;
  const reducedMotion = env.reducedMotion;

  // useId 含冒号，清理后用于 url(#id)
  const rawId = useId();
  const filterId = `lg-refrac-${rawId.replace(/[^a-zA-Z0-9_-]/g, '')}`;

  const interactions = useGlassInteractions({ draggable, reducedMotion, onPositionChange });

  // 按真实尺寸生成 SDF：ResizeObserver 保证圆角与位移剖面精确对齐
  const [size, setSize] = useState({ w: 0, h: 0 });
  useEffect(() => {
    const el = interactions.ref.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver((entries) => {
      const r = entries[0]?.contentRect;
      if (!r) return;
      // 取整到 4px，避免拖拽时因亚像素抖动反复生成 PNG
      const w = Math.round(r.width / 4) * 4;
      const h = Math.round(r.height / 4) * 4;
      setSize((prev) => (prev.w === w && prev.h === h ? prev : { w, h }));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [interactions.ref]);

  const texture = useMemo(() => {
    if (size.w < 8 || size.h < 8 || typeof document === 'undefined') return null;
    return buildSdfPixels({ width: size.w, height: size.h, radius });
  }, [size.w, size.h, radius]);

  // 融合时折射更紊乱，像两滴液体搅在一起
  const effectiveScale = distortionScale * (1 + merge * 0.55);
  const [r, g, b] = parseColor(tint);

  const vars: CSSProperties = {
    '--lg-blur': `${blur}px`,
    '--lg-tint': `rgba(${r}, ${g}, ${b}, 0.065)`,
    '--lg-tint-strong': `rgba(${r}, ${g}, ${b}, 0.16)`,
    '--lg-rgb': `${r}, ${g}, ${b}`,
    '--lg-glow': glow,
    '--lg-radius': `${radius}px`,
    '--lg-merge': merge,
    '--lg-tx': `${interactions.position.x}px`,
    '--lg-ty': `${interactions.position.y}px`,
    '--lg-press': interactions.pressed ? 0.954 : 1,
    '--lg-refract': mode === 'svg' && texture ? `url(#${filterId})` : 'none',
    '--lg-spec-boost': reducedMotion ? 0 : 1,
  } as CSSProperties;

  // 合并内部交互 ref 与外部 elementRef（融合场需要读取真实 DOMRect）
  const setRootRef = (el: HTMLDivElement | null) => {
    (interactions.ref as MutableRefObject<HTMLDivElement | null>).current = el;
    if (typeof elementRef === 'function') elementRef(el);
    else if (elementRef) (elementRef as MutableRefObject<HTMLDivElement | null>).current = el;
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (onActivate && (e.key === 'Enter' || e.key === ' ') && e.target === e.currentTarget) {
      e.preventDefault();
      onActivate();
      return;
    }
    interactions.handlers.onKeyDown(e);
    rest.onKeyDown?.(e);
  };

  // rest 里的事件由 handlers 覆盖；这里显式链式调用 rest 的同名 handler
  const { onPointerMove, onPointerDown, onPointerUp, onPointerCancel, onPointerLeave, onKeyDown: _restKeyDown, ...domRest } = rest;

  return (
    <div
      ref={setRootRef}
      className={`lg ${className}`.trim()}
      style={{ ...vars, ...style }}
      data-mode={mode}
      data-dragging={interactions.dragging || undefined}
      data-reduced={reducedMotion || undefined}
      data-pressed={interactions.pressed || undefined}
      tabIndex={draggable || onActivate ? 0 : undefined}
      role={onActivate ? 'button' : draggable ? 'group' : undefined}
      aria-label={ariaLabel}
      aria-keyshortcuts={draggable ? 'ArrowUp ArrowDown ArrowLeft ArrowRight Home' : undefined}
      onPointerMove={(e) => { interactions.handlers.onPointerMove(e); onPointerMove?.(e); }}
      onPointerDown={(e) => { interactions.handlers.onPointerDown(e); onPointerDown?.(e); }}
      onPointerUp={(e) => { interactions.handlers.onPointerUp(e); onPointerUp?.(e); }}
      onPointerCancel={(e) => { interactions.handlers.onPointerCancel(e); onPointerCancel?.(e); }}
      onPointerLeave={(e) => { interactions.handlers.onPointerLeave(e); onPointerLeave?.(e); }}
      onKeyDown={onKeyDown}
      onClickCapture={interactions.handlers.onClickCapture}
      {...domRest}
    >
      {/* SVG 滤镜定义：仅 Chromium 路径渲染；0 尺寸、不参与布局 */}
      {mode === 'svg' && texture && (
        <RefractionFilter id={filterId} textureUrl={texture.url} scale={effectiveScale} />
      )}

      {/* z1 折射：SDF 位移弯折背后内容 */}
      <div className="lg__refraction" aria-hidden="true" />

      {/* z2 磨砂：所有浏览器都有；Chromium 下与折射层串联构成「折射 → 磨砂」 */}
      <div className="lg__frost" aria-hidden="true" />

      {/* z3 边缘高光色散 + 指针跟随镜面高光 */}
      <div className="lg__edge" aria-hidden="true">
        <span className="lg__disp lg__disp--r" />
        <span className="lg__disp lg__disp--g" />
        <span className="lg__disp lg__disp--b" />
        <span className="lg__specular" />
      </div>

      {/* z4 内容层：不受任何滤镜影响 */}
      <div className="lg__content" style={contentStyle}>{children}</div>
    </div>
  );
}
