import { useRef } from 'react';
import { LiquidGlass } from './liquid-glass/LiquidGlass';
import { useMergeField } from './useMergeField';
import type { GlassParams } from './liquid-glass/types';

const BLOBS = [
  { key: 'A', cls: 'fusion-blob--a', radius: 26, hint: '长条' },
  { key: 'B', cls: 'fusion-blob--b', radius: 999, hint: '圆形' },
  { key: 'C', cls: 'fusion-blob--c', radius: 999, hint: '圆形' },
];

export function FusionPlayground({ params }: { params: GlassParams }) {
  const areaRef = useRef<HTMLDivElement>(null);
  const field = useMergeField(BLOBS.length, areaRef, 150);

  return (
    <div className="fusion-area" ref={areaRef}>
      <p className="fusion-area__hint">
        拖动玻璃块让它们靠近 → 轮廓形变、折射增强、边缘光晕连成液体。
        聚焦后也可用 <kbd>方向键</kbd> 移动、<kbd>Home</kbd> 复位。
      </p>

      {/* 纯高光连接带，不是另一块玻璃 */}
      {field.bridges.map((b, i) => {
        const dx = b.x2 - b.x1;
        const dy = b.y2 - b.y1;
        const len = Math.hypot(dx, dy);
        const angle = (Math.atan2(dy, dx) * 180) / Math.PI;
        return (
          <span
            key={i}
            className="fusion-bridge"
            aria-hidden="true"
            style={{
              left: b.x1,
              top: b.y1,
              width: len,
              height: 6 + b.strength * 18,
              transform: `translateY(-50%) rotate(${angle}deg)`,
              opacity: 0.12 + b.strength * 0.62,
            }}
          />
        );
      })}

      {BLOBS.map((blob, i) => (
        <LiquidGlass
          key={blob.key}
          {...params}
          radius={blob.radius}
          draggable
          elementRef={field.setRef(i)}
          merge={field.merges[i] ?? 0}
          onPositionChange={field.recompute}
          className={`fusion-blob ${blob.cls}`}
          ariaLabel={`可拖拽玻璃块 ${blob.key}（${blob.hint}），方向键移动，Home 复位`}
        >
          <span className="fusion-blob__label">{blob.key}</span>
        </LiquidGlass>
      ))}
    </div>
  );
}
