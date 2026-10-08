package com.linedraw.app.data

/** 全自動開始前要先排除的狀況；只回報最先該處理的一項，介面依此帶使用者去對的地方。 */
enum class StartBlock(val title: String, val message: String) {
    SERVICE("還沒啟用抽選輔助", "LineDraw 要靠 Android 的無障礙服務才能替你在 LINE 裡點擊。啟用「LineDraw 全自動抽選輔助」後再回來按一次。"),
    LINE_MISSING("找不到 LINE", "請先安裝 LINE 並登入要抽選的帳號。若使用分身、工作設定檔或安全資料夾，LINE 與 LineDraw 要裝在同一個空間。"),
    OFFLINE("目前沒有網路", "同步清單與開啟活動都需要網路，連上後再開始。"),
    NOTHING_READY("目前沒有可抽選的活動", "")
}

data class CatalogCounts(val ready: Int = 0, val notStarted: Int = 0, val unknown: Int = 0, val recorded: Int = 0) {
    val total get() = ready + notStarted + unknown + recorded
    /** 沒有可抽時要讓人看得出原因，所以其餘各類只要有就列出來。 */
    val summary: String get() = (listOf("可抽選 $ready 筆") + listOfNotNull(
        "尚未開始 $notStarted".takeIf { notStarted > 0 }, "時間未確認 $unknown".takeIf { unknown > 0 },
        "已有紀錄 $recorded".takeIf { recorded > 0 })).joinToString(" · ")
}

object Preflight {
    /** 已有紀錄優先於時間狀態：抽過的活動不論是否還在期間內都不會再排入。已截止的不計。 */
    fun counts(draws: List<Draw>, recorded: Set<String>, now: Long): CatalogCounts {
        var counts = CatalogCounts()
        for (draw in draws.filterNot { it.archived }.distinctBy { it.activityKey }) counts = when {
            draw.activityKey in recorded -> counts.copy(recorded = counts.recorded + 1)
            draw.runnable(now) -> counts.copy(ready = counts.ready + 1)
            draw.eligibility(now) == Eligibility.NOT_STARTED -> counts.copy(notStarted = counts.notStarted + 1)
            draw.eligibility(now) == Eligibility.UNKNOWN -> counts.copy(unknown = counts.unknown + 1)
            else -> counts
        }
        return counts
    }

    /** 清單是空的不算擋：還沒同步過，開始時會先同步。 */
    fun block(serviceEnabled: Boolean, lineInstalled: Boolean, online: Boolean, counts: CatalogCounts): StartBlock? = when {
        !serviceEnabled -> StartBlock.SERVICE
        !lineInstalled -> StartBlock.LINE_MISSING
        !online -> StartBlock.OFFLINE
        counts.total > 0 && counts.ready == 0 -> StartBlock.NOTHING_READY
        else -> null
    }
}
