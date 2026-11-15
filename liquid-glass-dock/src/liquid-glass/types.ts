import type { CSSProperties, HTMLAttributes, ReactNode, Ref } from 'react';

/** 四个对外暴露的光学参数 */
export interface GlassParams {
  /** feDisplacementMap 的 scale：SDF 位移强度（CSS px） */
  distortionScale: number;
  /** 磨砂层 backdrop-filter 的模糊半径（CSS px） */
  blur: number;
  /** 玻璃着色，任意 CSS 颜色（hex / rgb()）；内部按 alpha 合成 */
  tint: string;
  /** 边缘高光与色散强度 0..1 */
  glow: number;
}

export const DEFAULT_PARAMS: GlassParams = {
  // 折射带铺满「轮廓 → 中心」、剖面平缓，经过轻度磨砂后仍能看到背景弯折。
  // blur 刻意压到 4px：实测 ≥8px 会把 SDF 位移细节抹平，观感退化成普通模糊玻璃。
  // 滑块仍可一路拉到 36px，那是用户主动选择的「重磨砂」，不是默认观感。
  distortionScale: 78,
  blur: 4,
  tint: '#bfe4ff',
  glow: 0.72,
};

/** svg = Chromium 走 SDF + feDisplacementMap；fallback = Safari/Firefox 走 backdrop-filter */
export type RenderMode = 'svg' | 'fallback';

export interface LiquidGlassProps extends Omit<HTMLAttributes<HTMLDivElement>, 'children'> {
  /** 内容层：与所有滤镜层是兄弟节点，绝不被 filter / backdrop-filter 影响 */
  children?: ReactNode;
  distortionScale?: number;
  blur?: number;
  tint?: string;
  glow?: number;
  /** 圆角，同时决定 SDF 轮廓 */
  radius?: number;
  /** 允许指针 / 键盘拖拽（方向键移动，Home 复位） */
  draggable?: boolean;
  /** 拖动时的回调，供容器计算多玻璃融合 */
  onPositionChange?: (pos: { x: number; y: number }) => void;
  /** 强制渲染模式；不传时自动检测 */
  mode?: RenderMode;
  /** 融合强度 0..1，由容器根据邻近玻璃距离注入 */
  merge?: number;
  /** 内容层额外样式 */
  contentStyle?: CSSProperties;
  className?: string;
  style?: CSSProperties;
  /** 键盘可达性标签 */
  ariaLabel?: string;
  /** 作为按钮使用时的点击回调 */
  onActivate?: () => void;
  /** 暴露根 DOM 节点，供容器计算多玻璃融合距离 */
  elementRef?: Ref<HTMLDivElement>;
}
