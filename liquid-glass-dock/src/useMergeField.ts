import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { MutableRefObject, RefObject } from 'react';

export interface FusionBridge {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  strength: number;
}

export interface MergeField {
  setRef: (index: number) => (el: HTMLDivElement | null) => void;
  merges: number[];
  bridges: FusionBridge[];
  recompute: () => void;
}

const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);

/** 两个矩形边到边的最短距离（重叠时为 0） */
function rectGap(a: DOMRect, b: DOMRect): number {
  const dx = Math.max(0, a.left - b.right, b.left - a.right);
  const dy = Math.max(0, a.top - b.bottom, b.top - a.bottom);
  return Math.hypot(dx, dy);
}

/**
 * 多玻璃融合场：读取每个实例的真实 DOMRect（含拖拽 transform），
 * 按距离输出每个玻璃的 merge 强度与两两之间的液桥。
 *
 * 融合**不新增玻璃层** —— 只是让已有玻璃的轮廓 / 折射强度 / 边缘光晕形变，
 * 中间用一条纯高光带连接，避免出现「玻璃叠玻璃」。
 */
export function useMergeField(
  count: number,
  containerRef: RefObject<HTMLElement>,
  threshold = 168,
): MergeField {
  const elsRef = useRef<Array<HTMLDivElement | null>>([]);
  const rafRef = useRef(0);
  const [merges, setMerges] = useState<number[]>(() => Array(count).fill(0));
  const [bridges, setBridges] = useState<FusionBridge[]>([]);

  const setters = useMemo(
    () =>
      Array.from({ length: count }, (_, i) => (el: HTMLDivElement | null) => {
        elsRef.current[i] = el;
      }),
    [count],
  );

  const recompute = useCallback(() => {
    if (rafRef.current) return;
    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = 0;
      const base = containerRef.current?.getBoundingClientRect();
      if (!base) return;
      const rects = Array.from({ length: count }, (_, i) => elsRef.current[i]?.getBoundingClientRect() ?? null);
      const centers = rects.map((r) =>
        r ? { x: r.left + r.width / 2 - base.left, y: r.top + r.height / 2 - base.top } : null,
      );

      const next = Array(count).fill(0) as number[];
      const nextBridges: FusionBridge[] = [];
      for (let i = 0; i < count; i++) {
        for (let j = i + 1; j < count; j++) {
          if (!rects[i] || !rects[j]) continue;
          const gap = rectGap(rects[i] as DOMRect, rects[j] as DOMRect);
          const s = clamp((threshold - gap) / threshold, 0, 1);
          const shaped = Math.pow(s, 1.35);
          next[i] = Math.max(next[i], shaped);
          next[j] = Math.max(next[j], shaped);
          if (s > 0.1 && centers[i] && centers[j]) {
            nextBridges.push({
              x1: centers[i]!.x, y1: centers[i]!.y,
              x2: centers[j]!.x, y2: centers[j]!.y,
              strength: s,
            });
          }
        }
      }
      setMerges((prev) => (prev.every((v, i) => Math.abs(v - next[i]) < 0.004) ? prev : next));
      setBridges(nextBridges);
    });
  }, [count, threshold, containerRef]);

  useEffect(() => {
    recompute();
    window.addEventListener('resize', recompute);
    return () => {
      window.removeEventListener('resize', recompute);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [recompute]);

  return { setRef: (i: number) => setters[i], merges, bridges, recompute };
}

/** 供 LiquidGlass 的 elementRef 直接使用的 MutableRefObject 版本（保持类型导出完整） */
export type ElementRefSlot = MutableRefObject<HTMLDivElement | null>;
