import { LiquidGlass } from './liquid-glass/LiquidGlass';

export interface DockItem {
  id: string;
  label: string;
  icon: JSX.Element;
}

/* 内联 SVG 图标，零依赖 */
const I = {
  home: (
    <><path d="M3 10.2 12 3l9 7.2" /><path d="M5.5 9v10.5h13V9" /><path d="M9.5 19.5v-6h5v6" /></>
  ),
  search: (<><circle cx="10.8" cy="10.8" r="6.6" /><path d="m16 16 4.4 4.4" /></>),
  heart: (<path d="M12 20.3S3.8 15.2 3.8 9.4a4.4 4.4 0 0 1 8.2-2.2 4.4 4.4 0 0 1 8.2 2.2c0 5.8-8.2 10.9-8.2 10.9Z" />),
  bell: (<><path d="M18 15.5V10a6 6 0 1 0-12 0v5.5L4 18h16l-2-2.5Z" /><path d="M10 21h4" /></>),
  user: (<><circle cx="12" cy="8" r="3.8" /><path d="M4.8 20.2a7.2 7.2 0 0 1 14.4 0" /></>),
};

const svgProps = {
  width: 22,
  height: 22,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.7,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
};

const ITEMS: DockItem[] = [
  { id: 'home', label: '首页', icon: <svg {...svgProps}>{I.home}</svg> },
  { id: 'search', label: '发现', icon: <svg {...svgProps}>{I.search}</svg> },
  { id: 'library', label: '收藏', icon: <svg {...svgProps}>{I.heart}</svg> },
  { id: 'alerts', label: '消息', icon: <svg {...svgProps}>{I.bell}</svg> },
  { id: 'me', label: '我的', icon: <svg {...svgProps}>{I.user}</svg> },
];

export interface LiquidDockProps {
  active: string;
  onChange: (id: string) => void;
  /** 由调试面板注入的四个参数 */
  distortionScale: number;
  blur: number;
  tint: string;
  glow: number;
}

/**
 * App 底栏成品：
 * 只有一块 LiquidGlass，图标按钮全部位于内容层（z4），原生 <button> 保证键盘与读屏可用。
 * 玻璃没有用在列表 / 正文内容层上。
 */
export function LiquidDock(props: LiquidDockProps) {
  const { active, onChange, ...params } = props;
  return (
    <LiquidGlass
      {...params}
      radius={30}
      className="app-dock"
      ariaLabel="底部导航栏"
    >
      <nav className="dock-nav" aria-label="主导航">
        {ITEMS.map((item) => (
          <button
            key={item.id}
            type="button"
            className={`dock-btn${active === item.id ? ' is-active' : ''}`}
            aria-current={active === item.id ? 'page' : undefined}
            aria-label={item.label}
            onClick={() => onChange(item.id)}
          >
            <span className="dock-btn__icon">{item.icon}</span>
            <span className="dock-btn__label">{item.label}</span>
          </button>
        ))}
      </nav>
    </LiquidGlass>
  );
}
