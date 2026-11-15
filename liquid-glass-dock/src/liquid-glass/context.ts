import { createContext, useContext } from 'react';
import type { RenderMode } from './types';

export interface GlassEnvironment {
  /** 全局渲染模式（调试面板可强制切到 fallback 验证兜底） */
  mode: RenderMode;
  /** 是否降级动态效果 */
  reducedMotion: boolean;
}

export const GlassEnvContext = createContext<GlassEnvironment>({
  mode: 'fallback',
  reducedMotion: false,
});

export const useGlassEnv = () => useContext(GlassEnvContext);
