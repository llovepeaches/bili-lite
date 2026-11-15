package com.example.glassdock

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/** 高对比彩色内容：Preview 里也方便肉眼看出胶囊采样了什么。 */
@Composable
private fun PreviewBackground() {
    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFFFDFDFF), Color(0xFFDCE6FA))))
            .padding(16.dp),
    ) {
        repeat(6) { index ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(96.dp)
                    .padding(bottom = 12.dp)
                    .background(
                        Brush.horizontalGradient(
                            listOf(
                                if (index % 2 == 0) Color(0xFFFF9FB2) else Color(0xFF7FB8FF),
                                Color.White,
                            )
                        ),
                        RoundedCornerShape(18.dp),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "内容 ${index + 1}",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color(0xFF1B1F27),
                )
            }
        }
    }
}

@Composable
private fun PreviewHost(tier: GlassTier, dark: Boolean = false) {
    MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
        GlassDockScaffold(
            items = SampleItems,
            selectedIndex = 1,
            onSelect = {},
            tier = tier,
        ) {
            PreviewBackground()
        }
    }
}

@Preview(name = "1 FULL / 浅色壁纸", showBackground = true)
@Composable
private fun PreviewFullLight() = PreviewHost(GlassTier.FULL)

@Preview(
    name = "2 BLUR / 深色模式",
    showBackground = true,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
private fun PreviewBlurDark() = PreviewHost(GlassTier.BLUR, dark = true)

@Preview(name = "3 FLAT / 低内存兜底", showBackground = true)
@Composable
private fun PreviewFlat() = PreviewHost(GlassTier.FLAT)

@Preview(name = "4 FLAT / 字体放大 200%", showBackground = true, fontScale = 2f)
@Composable
private fun PreviewFlatLargeFont() = PreviewHost(GlassTier.FLAT)
