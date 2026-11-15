package com.example.glassdock

/*
 * Backdrop 2.x 悬浮玻璃胶囊底栏
 * 依据官方教程 https://kyant.gitbook.io/backdrop/tutorials/glass-bottom-bar
 *
 * 版本：io.github.kyant0:backdrop:2.0.1（Maven Central，kmp 分支）
 * 只使用 2.x API：rememberLayerBackdrop / layerBackdrop / drawBackdrop /
 * effects { vibrancy(); blur(); lens() } / Highlight.Default / Shadow.Default。
 * 旧 alpha 的 rememberLiquidGlassProviderState / GlassStyle / refraction() 一律不用。
 *
 * 与教程的三处有意差异（按本项目的约束，不是笔误）：
 * 1) 教程 onDrawSurface 写死 Color.White.copy(alpha = 0.5f)；这里改为从
 *    MaterialTheme.colorScheme.surfaceContainer 派生，浅色背景压 30% 暗层，
 *    深色背景压少量白，保证浅色壁纸下 onSurface 文字可读。
 * 2) 教程 shape = { CircleShape }；这里用 RoundedCornerShape(percent = 50)，
 *    同样是 CornerBasedShape（lens 的硬性要求），但更明确表达胶囊。
 * 3) 教程只有一条 effects 链；这里按 SDK_INT / 低内存 / 省电拆成 FULL / BLUR /
 *    FLAT 三档，FLAT 完全不调用 drawBackdrop（库在 <31 仍会 recordLayer 建离屏层）。
 */

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kyant.backdrop.backdrops.LayerBackdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.shadow.Shadow

/** 三档降级：与库 Platform.kt 的 S(31) / TIRAMISU(33) 判定保持一致。 */
enum class GlassTier {
    /** API 33+ 且非低内存/省电：vibrancy + blur + lens + 色散 + 高光/阴影。 */
    FULL,

    /** API 31~32：只有磨砂模糊与库自带描边高光，不调用 lens。 */
    BLUR,

    /** <31 / isLowRamDevice / 省电：纯半透明 Surface，零离屏缓冲。 */
    FLAT,
}

/**
 * 判定当前档位。库内部也会用 isRenderEffectSupported() / isRuntimeShaderSupported()
 * 兜底，这里做外层判断是为了让 FLAT 档**完全绕过** drawBackdrop，避免 <31 的离屏开销。
 */
@Composable
fun rememberGlassTier(): GlassTier {
    val context = LocalContext.current
    val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
    val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    val lowRam = activityManager?.isLowRamDevice == true
    val powerSave = powerManager?.isPowerSaveMode == true
    return remember(lowRam, powerSave) {
        resolveGlassTier(Build.VERSION.SDK_INT, lowRam, powerSave)
    }
}

/**
 * 档位判定的纯逻辑（无 Android 依赖，可被 JVM 单元测试直接覆盖）。
 *
 * 规则与库 Platform.kt 的 S(31) / TIRAMISU(33) 判定保持一致：
 * - FULL：33+ 且非低内存/省电
 * - BLUR：31~32 且非低内存/省电
 * - FLAT：其余（含 <31、低内存设备、省电模式）
 */
internal fun resolveGlassTier(sdkInt: Int, lowRam: Boolean, powerSave: Boolean): GlassTier = when {
    sdkInt >= Build.VERSION_CODES.TIRAMISU && !lowRam && !powerSave -> GlassTier.FULL
    sdkInt >= Build.VERSION_CODES.S && !lowRam && !powerSave -> GlassTier.BLUR
    else -> GlassTier.FLAT
}

/** 底栏条目。icon 由调用方提供，避免组件强绑定某套图标包。 */
data class DockItem(
    val label: String,
    val icon: ImageVector,
    val contentDescription: String = label,
)

/**
 * 宿主：注册采样源 + 内容 + 悬浮玻璃胶囊。
 *
 * 层级关系（也是规避 RenderThread SIGSEGV 的关键）：
 * ```
 * Box(root, safeContentPadding)
 * ├─ Box(layerBackdrop(backdrop))   ← 采样源，只包住"背后内容"
 * │  └─ content()
 * └─ GlassDock(drawBackdrop(backdrop))  ← 兄弟节点，不把自己画进采样源
 * ```
 * 若把 layerBackdrop 放在 drawBackdrop 之后（或让玻璃的子节点也被采样），
 * 会形成"玻璃采样自己"的反馈环，官方 FAQ 记录为 RenderThread Fatal signal 11。
 *
 * @param captureEnabled 滚动时传 false 可冻结采样（复用上一帧捕获结果），
 *                       松手后恢复 true。默认 true，不改变默认行为。
 */
@Composable
fun GlassDockScaffold(
    items: List<DockItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    tier: GlassTier = rememberGlassTier(),
    captureEnabled: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    val backgroundColor = MaterialTheme.colorScheme.background

    // 教程 Step 2：背景色和内容都必须画进 backdrop。
    // 只画 drawContent() 时，胶囊超出内容的区域会采到透明像素，边缘出现空洞。
    val backdrop = rememberLayerBackdrop {
        drawRect(backgroundColor)
        drawContent()
    }

    Box(modifier.fillMaxSize().safeContentPadding()) {
        Box(
            Modifier
                .fillMaxSize()
                .then(if (captureEnabled) Modifier.layerBackdrop(backdrop) else Modifier)
        ) {
            content()
        }

        GlassDock(
            backdrop = backdrop,
            items = items,
            selectedIndex = selectedIndex,
            onSelect = onSelect,
            tier = tier,
        )
    }
}

@Composable
private fun BoxScope.GlassDock(
    backdrop: LayerBackdrop,
    items: List<DockItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    tier: GlassTier,
) {
    // CornerBasedShape 是 lens 的硬性要求；percent=50 保证任意尺寸下都是胶囊。
    val shape: CornerBasedShape = RoundedCornerShape(percent = 50)

    val surface = MaterialTheme.colorScheme.surfaceContainer
    val isLight = surface.perceivedLuminance() > 0.5f
    // 浅色背景压约 30% 暗层，深色背景压少量白；绝不是写死的纯白。
    val readabilityLayer = if (isLight) {
        Color.Black.copy(alpha = 0.30f)
    } else {
        Color.White.copy(alpha = 0.10f)
    }
    val flatColor = blend(surface, readabilityLayer)

    val glassModifier = when (tier) {
        GlassTier.FULL, GlassTier.BLUR -> Modifier.drawBackdrop(
            backdrop = backdrop,
            shape = { shape },
            effects = {
                // 官方强制顺序：color filter ⇒ blur ⇒ lens
                vibrancy()
                blur(4f.dp.toPx())
                // lens 只在 33+ 开；height 16dp ≤ 圆角 32dp，amount 32dp ≤ 胶囊短边 64dp。
                // chromaticAberration 提供轻微 RGB 色散。
                if (tier == GlassTier.FULL) {
                    lens(
                        16f.dp.toPx(),
                        32f.dp.toPx(),
                        chromaticAberration = true,
                    )
                }
            },
            highlight = { Highlight.Default },
            shadow = { Shadow.Default },
            onDrawSurface = {
                drawRect(surface.copy(alpha = 0.62f))
                drawRect(readabilityLayer)
            },
            // 不使用 layerBlock 做任何动画：静置时不无限缓动高光角度，也不做
            // 含玻璃父节点的 alpha 动画（会用离屏层裁掉扩散阴影）。
        )

        GlassTier.FLAT -> Modifier
            .background(flatColor, shape)
            .border(
                width = 1.dp,
                color = if (isLight) {
                    Color.White.copy(alpha = 0.35f)
                } else {
                    Color.White.copy(alpha = 0.12f)
                },
                shape = shape,
            )
    }

    Box(
        Modifier
            .align(Alignment.BottomCenter)
            // 悬浮不贴边：左右 16dp、底部 20dp（Material 3，不是 iOS HIG 贴边胶囊）
            .padding(horizontal = 16.dp)
            .padding(bottom = 20.dp)
            .fillMaxWidth()
            // 用 min 高度而非写死 64dp：字体放大到 200% 时内容可撑开，不会溢出裁切
            .heightIn(min = 64.dp)
            // 注意：这里没有同形状 .clip（会裁掉扩散高光/阴影），也没有同链
            // graphicsLayer / Offscreen（外层离屏会顶掉内部 RenderEffect）。
            .then(glassModifier)
    ) {
        // 内容层由库的 drawContent() 在 effect 链之外绘制，图标与文字保持锐利，
        // 永不套任何 RenderEffect，也不会被 blur 一起糊掉。
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEachIndexed { index, item ->
                DockTab(
                    item = item,
                    selected = index == selectedIndex,
                    onClick = { onSelect(index) },
                )
            }
        }
    }
}

@Composable
private fun RowScope.DockTab(
    item: DockItem,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val tint = if (selected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Column(
        modifier = Modifier
            .weight(1f)
            // 最小点击区 48dp（Material 3），不是 iOS 的 44pt
            .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
            // selectable 自带 selected 语义 + TalkBack 状态播报
            .selectable(selected = selected, role = Role.Tab, onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = item.contentDescription
            }
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(24.dp),
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = item.label,
            style = MaterialTheme.typography.labelMedium,
            color = tint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

/** 感知亮度，用于判断 surfaceContainer 是浅色还是深色。 */
internal fun Color.perceivedLuminance(): Float =
    0.2126f * red + 0.7152f * green + 0.0722f * blue

/** 把 overlay 按自身 alpha 叠到 base 上，供 FLAT 档得到单一不透明色。 */
internal fun blend(base: Color, overlay: Color): Color {
    val a = overlay.alpha
    return Color(
        red = base.red * (1f - a) + overlay.red * a,
        green = base.green * (1f - a) + overlay.green * a,
        blue = base.blue * (1f - a) + overlay.blue * a,
        alpha = 1f,
    )
}
