import { memo } from 'react';

export interface RefractionFilterProps {
  /** 唯一 id（不含冒号，可直接用于 url(#id)） */
  id: string;
  /** SDF 位移贴图的 PNG data URL：R=X / G=Y / B=高光 / 128=中性 */
  textureUrl: string;
  /** 直接映射到 feDisplacementMap 的 scale */
  scale: number;
}

/**
 * 真正的光学层，不是「半透明 + blur」：
 *   feImage(SDF) → feDisplacementMap(弯折背后内容) → feColorMatrix 抽 B 通道高光 → feBlend(screen)
 *
 * color-interpolation-filters="sRGB" 是硬性要求：默认 linearRGB 会把 128 的中性点换算偏，
 * 导致整块玻璃出现恒定漂移。
 *
 * 这个 filter 只用于 Chromium 的 backdrop-filter: url(#id)。
 * Safari / Firefox 不使用它，由磨砂层的函数式 backdrop-filter 兜底。
 */
export const RefractionFilter = memo(function RefractionFilter({
  id,
  textureUrl,
  scale,
}: RefractionFilterProps) {
  if (!textureUrl) return null;
  return (
    <svg className="lg-filter-defs" width="0" height="0" aria-hidden="true" focusable="false">
      <defs>
        <filter
          id={id}
          filterUnits="objectBoundingBox"
          x="0"
          y="0"
          width="1"
          height="1"
          colorInterpolationFilters="sRGB"
        >
          {/* 贴图默认铺满 filter region；preserveAspectRatio=none 让 SDF 精确对齐元素宽高 */}
          <feImage href={textureUrl} result="sdf" preserveAspectRatio="none" />
          <feDisplacementMap
            in="SourceGraphic"
            in2="sdf"
            scale={scale}
            xChannelSelector="R"
            yChannelSelector="G"
            result="warped"
          />
          {/* B 通道：减去中性 0.502 后只留下正高光，screen 叠回折射结果 */}
          <feColorMatrix
            in="sdf"
            type="matrix"
            values="0 0 1 0 -0.502
                    0 0 1 0 -0.502
                    0 0 1 0 -0.502
                    0 0 0 0 1"
            result="spec"
          />
          <feGaussianBlur in="spec" stdDeviation="0.7" result="softSpec" />
          <feBlend in="warped" in2="softSpec" mode="screen" />
        </filter>
      </defs>
    </svg>
  );
});
