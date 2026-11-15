import type { GlassParams } from './liquid-glass/types';

export const IMPORT_SNIPPET = `import { LiquidGlass } from './liquid-glass/LiquidGlass';
import './liquid-glass/liquid-glass.css';`;

export function usageSnippet(p: GlassParams): string {
  return `${IMPORT_SNIPPET}

// 四个光学参数都可调；内容层永远不被滤镜影响
export function MyDock() {
  return (
    <LiquidGlass
      distortionScale={${p.distortionScale}}   // SDF 位移强度 → feDisplacementMap scale
      blur={${p.blur}}                 // 磨砂层 backdrop-filter
      tint="${p.tint}"            // 玻璃着色
      glow={${p.glow}}                // 边缘高光 / RGB 色散
      radius={30}
      draggable                  // 指针拖拽 + 方向键 + Home
      className="app-dock"
    >
      <nav aria-label="主导航">
        <button type="button">首页</button>
        <button type="button">发现</button>
        <button type="button">我的</button>
      </nav>
    </LiquidGlass>
  );
}`;
}

export const ARCHITECTURE_SNIPPET = `// 四层分离（源码见 liquid-glass/LiquidGlass.tsx）
// z1 .lg__refraction  backdrop-filter: url(#SDF filter)   ← Chromium 弯折背后内容
// z2 .lg__frost       backdrop-filter: blur() saturate()   ← 所有浏览器兜底
// z3 .lg__edge        RGB 色散 + 指针跟随镜面高光
// z4 .lg__content     内容层（与上面三层是兄弟，不受滤镜影响）
//
// .lg 根元素不施加任何 filter / backdrop-filter / opacity。`;
