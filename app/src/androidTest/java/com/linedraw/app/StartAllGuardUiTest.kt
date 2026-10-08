package com.linedraw.app

import android.app.UiAutomation
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.linedraw.app.data.Draw
import com.linedraw.app.data.Metadata
import com.linedraw.app.engine.DrawAccessibilityService
import kotlinx.coroutines.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

/** 全自動按鈕的防呆：缺條件時帶去補，不會默默開始一批。只在專用模擬器執行。 */
@RunWith(AndroidJUnit4::class)
class StartAllGuardUiTest {
    @get:Rule val compose=createEmptyComposeRule()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private val app get()=instrumentation.targetContext.applicationContext as LineDrawApp
    private var scenario:ActivityScenario<MainActivity>?=null
    @Before fun setup() = runBlocking {
        ConsentFixtures.install(app)
        withContext(Dispatchers.IO) { app.repository.db.clearAllTables() }
        val now=System.currentTimeMillis()
        app.repository.dao.upsertDraws(listOf(
            Draw("row-ready","id-ready","coupon:1:ready","測試店","台北市","UX-03 魔導神杖","https://liff.line.me/1/c/ready","",now-60_000,now+600_000,0),
            Draw("row-later","id-later","coupon:1:later","測試店","台北市","CX-02 魔導至尊","https://liff.line.me/1/c/later","",now+600_000,now+900_000,1)))
        // 清單剛同步過：啟動時不會再同步，按鈕不會卡在同步中。
        app.repository.dao.meta(Metadata("lastSync",now.toString()))
        app.getSharedPreferences("preferences",0).edit().putBoolean("demo",false).putBoolean("fiveLinkArea",false).commit()
        val automation=instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        android.os.ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("settings put secure enabled_accessibility_services ''")).use { it.readBytes() }
        withTimeout(10_000) { while(DrawAccessibilityService.instance!=null) delay(100) }
        scenario=ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun close() { scenario?.close() }

    @Test fun withoutTheServiceTheButtonLeadsToSetupAndStartsNothing() {
        compose.onNodeWithTag("mainList").performScrollToNode(hasTestTag("startAll"))
        compose.onNodeWithTag("startAllStatus").assertTextContains("尚未啟用抽選輔助",substring=true)
        compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag("startAll") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("startAll").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("還沒啟用抽選輔助").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("還沒啟用抽選輔助").assertIsDisplayed()
        compose.onNodeWithTag("confirmStartAll").assertDoesNotExist()
        compose.onNodeWithText("前往設定").performClick()
        compose.onNodeWithText("啟用抽選輔助").assertIsDisplayed()
        assertNull(runBlocking { app.repository.dao.latestBatch() })
    }
}
