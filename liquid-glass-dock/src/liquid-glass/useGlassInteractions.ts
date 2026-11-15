import { useCallback, useEffect, useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent as ReactPointerEvent, RefObject } from 'react';

export interface Point {
  x: number;
  y: number;
}

export interface GlassInteractionOptions {
  draggable: boolean;
  reducedMotion: boolean;
  onPositionChange?: (pos: Point) => void;
}

export interface GlassInteraction {
  ref: RefObject<HTMLDivElement>;
  position: Point;
  pressed: boolean;
  dragging: boolean;
  handlers: {
    onPointerMove: (e: ReactPointerEvent<HTMLDivElement>) => void;
    onPointerDown: (e: ReactPointerEvent<HTMLDivElement>) => void;
    onPointerUp: (e: ReactPointerEvent<HTMLDivElement>) => void;
    onPointerCancel: (e: ReactPointerEvent<HTMLDivElement>) => void;
    onPointerLeave: (e: ReactPointerEvent<HTMLDivElement>) => void;
    onKeyDown: (e: KeyboardEvent<HTMLDivElement>) => void;
    onClickCapture: (e: React.MouseEvent<HTMLDivElement>) => void;
  };
  reset: () => void;
}

/**
 * 指针跟随高光 + 按压缩放 + 可拖拽 + 键盘操作。
 * 高光坐标只写 CSS 变量（rAF 节流），不触发 React 重渲染；
 * 位置变化才 setState 并通知容器做融合计算。
 */
export function useGlassInteractions(opts: GlassInteractionOptions): GlassInteraction {
  const { draggable, reducedMotion, onPositionChange } = opts;
  const ref = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState<Point>({ x: 0, y: 0 });
  const [pressed, setPressed] = useState(false);
  const [dragging, setDragging] = useState(false);

  const posRef = useRef<Point>({ x: 0, y: 0 });
  const startRef = useRef({ px: 0, py: 0, x: 0, y: 0, active: false, moved: false, pointerId: -1 });
  const justDragged = useRef(false);
  const rafRef = useRef(0);
  const pending = useRef<{ mx: number; my: number } | null>(null);

  useEffect(() => () => { if (rafRef.current) cancelAnimationFrame(rafRef.current); }, []);

  const flushHighlight = useCallback(() => {
    rafRef.current = 0;
    const p = pending.current;
    const el = ref.current;
    if (!p || !el) return;
    el.style.setProperty('--lg-mx', `${p.mx.toFixed(2)}%`);
    el.style.setProperty('--lg-my', `${p.my.toFixed(2)}%`);
  }, []);

  const scheduleHighlight = useCallback(() => {
    if (!rafRef.current) rafRef.current = requestAnimationFrame(flushHighlight);
  }, [flushHighlight]);

  const commitPosition = useCallback(
    (next: Point) => {
      posRef.current = next;
      setPosition(next);
      onPositionChange?.(next);
    },
    [onPositionChange],
  );

  const onPointerMove = useCallback(
    (e: ReactPointerEvent<HTMLDivElement>) => {
      // ① 指针跟随高光（reduced-motion 下完全跳过）
      if (!reducedMotion) {
        const rect = e.currentTarget.getBoundingClientRect();
        if (rect.width && rect.height) {
          pending.current = {
            mx: ((e.clientX - rect.left) / rect.width) * 100,
            my: ((e.clientY - rect.top) / rect.height) * 100,
          };
          scheduleHighlight();
        }
        e.currentTarget.style.setProperty('--lg-hover', '1');
      }

      // ② 拖拽：超过 4px 阈值才进入，避免吞掉普通点击
      const s = startRef.current;
      if (!s.active || !draggable) return;
      const dx = e.clientX - s.px;
      const dy = e.clientY - s.py;
      if (!s.moved && Math.hypot(dx, dy) < 4) return;
      s.moved = true;
      setDragging(true);
      commitPosition({ x: s.x + dx, y: s.y + dy });
    },
    [reducedMotion, draggable, scheduleHighlight, commitPosition],
  );

  const onPointerDown = useCallback(
    (e: ReactPointerEvent<HTMLDivElement>) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      startRef.current = {
        px: e.clientX,
        py: e.clientY,
        x: posRef.current.x,
        y: posRef.current.y,
        active: true,
        moved: false,
        pointerId: e.pointerId,
      };
      setPressed(true);
      if (draggable) {
        try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* 忽略 */ }
      }
    },
    [draggable],
  );

  const finish = useCallback((e: ReactPointerEvent<HTMLDivElement>) => {
    const s = startRef.current;
    justDragged.current = s.moved;
    s.active = false;
    setPressed(false);
    setDragging(false);
    try { e.currentTarget.releasePointerCapture(s.pointerId); } catch { /* 忽略 */ }
  }, []);

  const onPointerLeave = useCallback((e: ReactPointerEvent<HTMLDivElement>) => {
    if (!reducedMotion) e.currentTarget.style.setProperty('--lg-hover', '0.28');
  }, [reducedMotion]);

  const reset = useCallback(() => {
    commitPosition({ x: 0, y: 0 });
  }, [commitPosition]);

  const onKeyDown = useCallback(
    (e: KeyboardEvent<HTMLDivElement>) => {
      if (!draggable || e.target !== e.currentTarget) return;
      const step = e.shiftKey ? 40 : 12;
      let dx = 0;
      let dy = 0;
      switch (e.key) {
        case 'ArrowLeft': dx = -step; break;
        case 'ArrowRight': dx = step; break;
        case 'ArrowUp': dy = -step; break;
        case 'ArrowDown': dy = step; break;
        case 'Home': e.preventDefault(); reset(); return;
        default: return;
      }
      e.preventDefault();
      commitPosition({ x: posRef.current.x + dx, y: posRef.current.y + dy });
    },
    [draggable, reset, commitPosition],
  );

  // 拖拽结束后的那一次 click 不应触发按钮
  const onClickCapture = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (justDragged.current) {
      e.preventDefault();
      e.stopPropagation();
      justDragged.current = false;
    }
  }, []);

  return {
    ref,
    position,
    pressed,
    dragging,
    handlers: {
      onPointerMove,
      onPointerDown,
      onPointerUp: finish,
      onPointerCancel: finish,
      onPointerLeave,
      onKeyDown,
      onClickCapture,
    },
    reset,
  };
}
