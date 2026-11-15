package com.example.glassdock

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 玻璃底栏里**不依赖 Android 运行时**的纯逻辑单元测试。
 *
 * 覆盖三件事：
 * 1. 三档降级判定（API 阈值、低内存、省电模式）；
 * 2. 感知亮度（决定浅色压暗 / 深色压白）；
 * 3. overlay 混合（FLAT 档的不透明底色）。
 *
 * 这些是本工程里唯一能在无设备环境下被真正执行验证的部分；
 * 折射 / 色散 / 高光的实际观感仍需真机（README「验收」一节给了步骤）。
 */
class GlassDockLogicTest {

    // ---- 三档降级 ---------------------------------------------------------

    @Test
    fun `API 33 及以上且非低内存省电为 FULL`() {
        assertEquals(GlassTier.FULL, resolveGlassTier(33, lowRam = false, powerSave = false))
        assertEquals(GlassTier.FULL, resolveGlassTier(34, lowRam = false, powerSave = false))
        assertEquals(GlassTier.FULL, resolveGlassTier(37, lowRam = false, powerSave = false))
    }

    @Test
    fun `API 31 到 32 为 BLUR`() {
        assertEquals(GlassTier.BLUR, resolveGlassTier(31, lowRam = false, powerSave = false))
        assertEquals(GlassTier.BLUR, resolveGlassTier(32, lowRam = false, powerSave = false))
    }

    @Test
    fun `API 30 及以下为 FLAT`() {
        assertEquals(GlassTier.FLAT, resolveGlassTier(30, lowRam = false, powerSave = false))
        assertEquals(GlassTier.FLAT, resolveGlassTier(23, lowRam = false, powerSave = false))
    }

    @Test
    fun `低内存设备一律降为 FLAT`() {
        assertEquals(GlassTier.FLAT, resolveGlassTier(37, lowRam = true, powerSave = false))
        assertEquals(GlassTier.FLAT, resolveGlassTier(33, lowRam = true, powerSave = false))
        assertEquals(GlassTier.FLAT, resolveGlassTier(31, lowRam = true, powerSave = false))
    }

    @Test
    fun `省电模式一律降为 FLAT`() {
        assertEquals(GlassTier.FLAT, resolveGlassTier(37, lowRam = false, powerSave = true))
        assertEquals(GlassTier.FLAT, resolveGlassTier(33, lowRam = false, powerSave = true))
        assertEquals(GlassTier.FLAT, resolveGlassTier(31, lowRam = false, powerSave = true))
    }

    @Test
    fun `降级只降不升_BLR档不会因低内存回退到更高档`() {
        // 31~32 在低内存下应落 FLAT，而不是被提升为 FULL
        assertEquals(GlassTier.FLAT, resolveGlassTier(32, lowRam = true, powerSave = false))
    }

    // ---- 感知亮度 ---------------------------------------------------------

    @Test
    fun `感知亮度_白为1_黑为0`() {
        assertEquals(1f, Color.White.perceivedLuminance(), 0.001f)
        assertEquals(0f, Color.Black.perceivedLuminance(), 0.001f)
    }

    @Test
    fun `感知亮度_纯红约等于02126`() {
        // 0.2126 * 1 + 0.7152 * 0 + 0.0722 * 0
        assertEquals(0.2126f, Color.Red.perceivedLuminance(), 0.001f)
    }

    @Test
    fun `感知亮度_可据此区分浅深色面`() {
        assertTrue(Color(0xFFF7F7FB).perceivedLuminance() > 0.5f)
        assertTrue(Color(0xFF1B1B1F).perceivedLuminance() < 0.5f)
    }

    // ---- overlay 混合 -----------------------------------------------------

    @Test
    fun `混合_黑色30覆盖白色得到约七成灰`() {
        val mixed = blend(Color.White, Color.Black.copy(alpha = 0.30f))
        assertEquals(0.7f, mixed.red, 0.01f)
        assertEquals(0.7f, mixed.green, 0.01f)
        assertEquals(0.7f, mixed.blue, 0.01f)
        assertEquals(1f, mixed.alpha, 0.001f)
    }

    @Test
    fun `混合_不透明覆盖完全替换原色`() {
        val mixed = blend(Color.White, Color.Black.copy(alpha = 1f))
        assertEquals(0f, mixed.red, 0.001f)
        assertEquals(0f, mixed.green, 0.001f)
        assertEquals(0f, mixed.blue, 0.001f)
        assertEquals(1f, mixed.alpha, 0.001f)
    }

    @Test
    fun `混合_全透明覆盖时保持原色`() {
        val mixed = blend(Color(0xFF3366CC), Color.Black.copy(alpha = 0f))
        assertEquals(0x33 / 255f, mixed.red, 0.01f)
        assertEquals(0x66 / 255f, mixed.green, 0.01f)
        assertEquals(0xCC / 255f, mixed.blue, 0.01f)
    }
}
