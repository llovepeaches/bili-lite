# Liquid Glass Dock

可交互的 **React + TypeScript** 液态玻璃底栏。折射是真实的 SDF 位移贴图 + `feDisplacementMap`，不是「半透明 + blur」冒充。

```bash
pnpm install
pnpm dev       # http://localhost:5173
pnpm build     # tsc --noEmit + vite build
pnpm preview   # http://localhost:4173，预览生产构建
```

打开页面后：左侧是 App 底栏预览，右侧是四个参数的滑块面板、SDF 通道预览、复制当前参数按钮，以及多玻璃融合实验区。

---

## 1. 四个 props

```tsx
<LiquidGlass
  distortionScale={78}   // → feDisplacementMap 的 scale（CSS px）
  blur={4}               // → 磨砂层 backdrop-filter: blur()
  tint="#bfe4ff"         // → 玻璃着色（自动按 alpha 合成）
  glow={0.72}            // → 边缘高光 / RGB 色散 / 指针镜面高光
  radius={30}
  draggable              // 指针拖拽 + 方向键 + Home
>
  <nav>{/* 按钮在内容层，始终清晰可点 */}</nav>
</LiquidGlass>
```

`distortionScale` 直接映射到 SVG filter 的 `scale`；贴图本身只编码位移**方向与剖面**，所以调参不需要重新生成 PNG。

## 2. 光学：SDF 位移贴图

`src/liquid-glass/sdf.ts` 用 canvas 逐像素生成 PNG data URL：

| 通道 | 含义 | 中性 |
| --- | --- | --- |
| R | X 方向位移 | `128` |
| G | Y 方向位移 | `128` |
| B | 镜面高光（左上光源） | `128` |
| A | 恒为 255（避免 premultiplied alpha 污染通道） | — |

- 用**圆角矩形有符号距离场**求轮廓，数值梯度得到单位法线；位移沿「轮廓 → 中心」按平缓剖面衰减（`bandRatio` 以半短边归一化），轮廓最强、正中央归零为 `128` 中性，中央内容不被整体推偏。
- 采样点沿 **-法线**（向中心）偏移，边缘内容向外扩张，形成凸透镜放大感。
- `feDisplacementMap` 的公式是 `sampleXY = P + scale * (channel - 0.5)`，所以 128 ≈ 零位移。
- **filter 必须写 `color-interpolation-filters="sRGB"`**：默认 linearRGB 会把 0.5 换算成 sRGB ≈ 0.735，中性点整体漂移、玻璃会出现恒定偏折。
- B 通道经 `feColorMatrix` 减去中性 `0.502` 后只留下正高光，再 `feBlend mode="screen"` 叠回折射结果。

滤镜链（`src/liquid-glass/RefractionFilter.tsx`）：

```
feImage(SDF) ──┬─→ feDisplacementMap(SourceGraphic, R/G) ──→ warped ─┐
               └─→ feColorMatrix(B - 0.502) → feGaussianBlur ─────────┴→ feBlend(screen)
```

## 3. 分层：内容层绝不被滤镜影响

```
.lg                       ← 根元素：无 filter / backdrop-filter / opacity
├─ svg defs               ← filter 定义（0 尺寸，不参与布局）
├─ .lg__refraction  z1   ← backdrop-filter: url(#SDF filter)   Chromium 弯折背后内容
├─ .lg__frost       z2   ← backdrop-filter: blur() saturate()   所有浏览器
├─ .lg__edge        z3   ← RGB 三色边框色散 + 指针跟随镜面高光
└─ .lg__content     z4   ← 内容层（兄弟节点），原生 <button>，锐利可点
```

前三层都是 `position:absolute; inset:0; border-radius:inherit; aria-hidden; pointer-events:none`。
**根元素不施加任何滤镜**是内容层保持清晰的关键——把 `filter` 挂在父容器上是这类组件最常见的错误。

## 4. 交互

| 能力 | 实现 |
| --- | --- |
| 指针跟随高光 | `pointermove` 只写 `--lg-mx/--lg-my` CSS 变量，rAF 节流，不触发 React 重渲染 |
| 按压缩放回弹 | `--lg-press: 0.954 → 1`，`transition: .55s cubic-bezier(.22,1,.36,1)` |
| 可拖拽 | pointer capture + **4px 阈值**（不吞普通点击）；拖拽期间 `transition:none` 保证跟手，松手后恢复过渡 |
| 融合形变 | `useMergeField` 读真实 `DOMRect` 算边到边距离 → `merge` 提升 `scale`、收紧圆角、扩出高光光晕；中间只画一条纯高光连接带 |
| 键盘 | 玻璃块 `tabIndex=0`，方向键移动（Shift 加速 40px）、`Home` 复位、`aria-keyshortcuts`；底栏按钮是原生 `<button>`，`:focus-visible` 有明显描边 |
| reduced-motion | `matchMedia('(prefers-reduced-motion: reduce)')` + 面板强制开关；关闭指针跟随、所有过渡/动画置零，静态折射保留 |

融合**不新增玻璃层**：只是让已有玻璃的轮廓、折射强度、边缘光晕形变，避免「玻璃叠玻璃」。

## 5. 兼容策略（不出现空白）

| 环境 | 路径 |
| --- | --- |
| Chromium（Chrome / Edge / Opera） | `backdrop-filter: url(#lg-refrac-*)`，真正用 SDF 弯折背后内容；磨砂层串联在后，构成「折射 → 磨砂」 |
| Safari / Firefox | 自动检测后走 `fallback`：`url()` 层关闭，只保留函数式 `blur() saturate()` + tint 渐变 + 边缘高光 |
| 连函数式 backdrop-filter 都没有 | `@supports not (...)` 给 `.lg__frost` 实色 `rgba(28,40,66,.9)`，玻璃依旧可见、内容依旧可点 |

面板里的「自动 / 强制 SVG / 强制兜底」可以直接切换验证两条路径。

## 6. 使用示例

完整可运行示例见 `src/App.tsx`、`src/LiquidDock.tsx`、`src/FusionPlayground.tsx`，以及面板底部「使用示例 / 分层结构」折叠区（会用当前参数实时生成代码，「复制当前参数」按钮把同一段 TSX 写进剪贴板）。

最小化用法：

```tsx
import { LiquidGlass } from './liquid-glass/LiquidGlass';
import './liquid-glass/liquid-glass.css';

export function MyDock() {
  return (
    <LiquidGlass distortionScale={78} blur={4} tint="#bfe4ff" glow={0.72} radius={30}>
      <nav aria-label="主导航">
        <button type="button">首页</button>
        <button type="button">发现</button>
        <button type="button">我的</button>
      </nav>
    </LiquidGlass>
  );
}
```

## 7. 禁止项如何规避

- **只用半透明 + blur 冒充** → 折射层是 `feDisplacementMap`，面板可实时查看 R/G/B 通道贴图；把 `distortionScale` 拉到 0 才是纯磨砂。
- **玻璃叠玻璃** → 一个实例只有一组光学层；融合区三个实例彼此独立，靠近时靠形变而非叠加；底栏内部只有一组层。
- **玻璃用在列表 / 正文内容层** → 列表卡片是 `rgba(16,24,50,.78)` 实色普通卡片，调试面板是 `#101731` 实色面板，正文文字没有任何 backdrop-filter；玻璃只出现在底栏与融合实验区的控件上。

## 8. 默认参数为什么是 78 / 4 / #bfe4ff / 0.72

| 参数 | 取值 | 依据 |
| --- | --- | --- |
| `distortionScale` | 78 | 经过 4px 磨砂后仍能把背景斜条纹明显弯成弧形；拉到 0 可对照「无位移」的纯磨砂 |
| `blur` | 4 | 独立 filter-probe 实测：`0 / 2 / 4px` 弯折清晰，`≥8px` 会把 SDF 位移细节抹平，观感退化成普通模糊玻璃。滑块仍可到 36px，那是用户主动选的「重磨砂」，不是默认观感 |
| `tint` / `glow` | `#bfe4ff` / 0.72 | 低 alpha 着色，不盖掉折射；边缘高光足够明显但不糊文字 |

SDF 剖面刻意做得平缓（`(1-t)^0.85`），让形变成为低频大尺度弯折而不是轮廓上一圈细线；背景条纹也随之加粗，避免被 `backdrop-filter` 抹成均匀色。

## 9. 验收（Chromium / Playwright）

```bash
pnpm build && pnpm preview      # 终端 A
python3 scripts/verify.py       # 终端 B，需 playwright + Pillow；可用 LG_URL 改地址
```

`pnpm build`：`tsc --noEmit` 零错误 + `vite build` 45 modules，产物 CSS 13.85 kB / JS 165.80 kB（gzip 55.54 kB）。

`preview/verification.json` 记录 **34 项自动检查，全部通过**：

| 维度 | 关键结果 |
| --- | --- |
| 光学 | `backdrop-filter: url(#lg-refrac-*)` 生效、`feDisplacementMap` 用 R/G、`scale=78`、`color-interpolation-filters="sRGB"`；SDF 中心像素 `[128,128,128]`，偏差 中心 0 → 1/4 处 58 → 轮廓 112 递增；`scale 0→140` 底栏平均 RGB 差 **8.77** |
| 分层 | 根元素与内容层 `filter/backdrop-filter=none`、`opacity=1`，四层 z-index `1/2/3/4`；按钮点击与键盘 Enter 均生效 |
| 交互 | 指针高光 `3.49% → 96.51%`、按压 `0.954 → 1`、拖拽 `tx 0→70px / ty 34px`、方向键 `70→82px`、Home 复位 `0`、融合 merge 合计 `1.880` + 3 条连接带 |
| 兼容 | fallback 下 `feDisplacementMap` 数为 0，函数式 `blur(4px) saturate(1.6)` 仍在，底栏亮度 std **21.74**（不空白）；reduced-motion 降级 `data-reduced` + `--lg-spec-boost:0` + 过渡 0s |
| 禁止项 | 底栏内无嵌套 `.lg`，正文卡片 `backdrop-filter:none`，全页仅 4 处玻璃 |
| 稳定性 | 控制台 / 页面零错误 |

截图在 `preview/`：`01-full-svg.png` 全页、`02-dock-svg.png` 底栏、`03-panel-sdf.png` 通道面板、`04/05` 融合前后、`08-refraction-compare.png`（scale 0 vs 140 对比）、`09-dock-fallback.png` 兜底路径。

## 10. 文件清单

| 文件 | 作用 |
| --- | --- |
| `src/liquid-glass/sdf.ts` | SDF 位移贴图生成、PNG 编码、面板预览绘制 |
| `src/liquid-glass/RefractionFilter.tsx` | SVG filter 定义（feImage / feDisplacementMap / B 通道高光） |
| `src/liquid-glass/LiquidGlass.tsx` | 四层组件、ResizeObserver 按尺寸生成贴图 |
| `src/liquid-glass/useGlassInteractions.ts` | 指针高光 / 按压 / 拖拽 / 键盘 |
| `src/liquid-glass/useReducedMotion.ts` | 减少动态效果 |
| `src/liquid-glass/detect.ts` | 渲染路径检测 + 颜色解析 |
| `src/liquid-glass/context.ts` | 全局 mode / reducedMotion |
| `src/liquid-glass/types.ts` | props 类型与默认参数 |
| `src/liquid-glass/liquid-glass.css` | 四层样式、兜底、reduced-motion |
| `src/LiquidDock.tsx` | App 底栏成品 |
| `src/FusionPlayground.tsx` / `src/useMergeField.ts` | 多玻璃融合 |
| `src/ControlPanel.tsx` | 滑块面板、复制参数、SDF 预览、示例代码 |
| `src/examples.ts` | 使用示例代码生成 |
| `src/App.tsx` / `src/styles.css` | 演示页与背景场景 |
| `scripts/verify.py` | Playwright 自动验收（34 项） |
| `preview/` | 验收截图与 `verification.json` |
