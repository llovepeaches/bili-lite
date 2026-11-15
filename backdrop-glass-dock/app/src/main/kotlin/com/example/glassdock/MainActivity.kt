package com.example.glassdock

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

internal val SampleItems = listOf(
    DockItem(label = "首页", icon = Icons.Default.Home, contentDescription = "首页标签"),
    DockItem(label = "搜索", icon = Icons.Default.Search, contentDescription = "搜索标签"),
    DockItem(label = "收藏", icon = Icons.Default.Favorite, contentDescription = "收藏标签"),
    DockItem(label = "设置", icon = Icons.Default.Settings, contentDescription = "设置标签"),
)

/** 最小可运行示例：动态配色 + 深色模式 + 彩色背景内容（用来肉眼验证折射与色散）。 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val context = LocalContext.current
            val dark = isSystemInDarkTheme()
            val colorScheme = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            } else if (dark) {
                darkColorScheme()
            } else {
                lightColorScheme()
            }

            MaterialTheme(colorScheme = colorScheme) {
                var selected by remember { mutableIntStateOf(0) }
                val listState = rememberLazyListState()

                GlassDockScaffold(
                    items = SampleItems,
                    selectedIndex = selected,
                    onSelect = { selected = it },
                    // 滚动时冻结 backdrop 捕获，松手后恢复；静置时不产生额外重录。
                    captureEnabled = !listState.isScrollInProgress,
                ) {
                    SampleContent(listState)
                }
            }
        }
    }
}

@Composable
private fun SampleContent(listState: LazyListState) {
    val palette = listOf(
        Color(0xFFFFB3C1),
        Color(0xFF9AD0FF),
        Color(0xFFB8E6B0),
        Color(0xFFFFD79A),
        Color(0xFFC9B6FF),
        Color(0xFF8FE0E0),
    )
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFFF7F7FB), Color(0xFFE8ECF5))
                )
            ),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = 16.dp,
            top = 24.dp,
            end = 16.dp,
            bottom = 120.dp, // 给悬浮胶囊留空间
        ),
    ) {
        items(palette.size) { index ->
            Column {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(132.dp)
                        .background(
                            Brush.horizontalGradient(
                                listOf(palette[index], Color.White)
                            ),
                            RoundedCornerShape(20.dp),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "背景内容 ${index + 1}",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color(0xFF20242C),
                    )
                }
                Text(
                    text = "这条正文会被玻璃胶囊采样、模糊并在边缘折射。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        }
    }
}
