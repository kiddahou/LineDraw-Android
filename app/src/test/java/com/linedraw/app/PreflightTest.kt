package com.linedraw.app

import com.linedraw.app.data.*
import org.junit.Assert.*
import org.junit.Test

class PreflightTest {
    private val now = 1_000_000L
    private fun draw(key: String, start: Long?, end: Long?, archived: Boolean = false) =
        Draw(key, key, key, "店", "台北市", "UX-03", "https://lin.ee/$key", "", start, end, 0, archived = archived)

    @Test fun countsSplitByWhyADrawCanOrCannotRun() {
        val draws = listOf(draw("ready", now - 10, now + 10), draw("later", now + 10, now + 20), draw("notime", null, null),
            draw("done", now - 10, now + 10), draw("expired", now - 20, now - 10), draw("gone", now - 10, now + 10, archived = true))
        assertEquals(CatalogCounts(ready = 1, notStarted = 1, unknown = 1, recorded = 1), Preflight.counts(draws, setOf("done"), now))
    }
    @Test fun sameActivityListedTwiceCountsOnce() {
        val twice = listOf(draw("a", now - 10, now + 10), draw("a", now - 10, now + 10).copy(rowKey = "other-row"))
        assertEquals(1, Preflight.counts(twice, emptySet(), now).ready)
    }
    @Test fun summaryOnlyNamesNonEmptyGroups() {
        assertEquals("可抽選 3 筆", CatalogCounts(ready = 3).summary)
        assertEquals("可抽選 0 筆 · 尚未開始 2 · 已有紀錄 5", CatalogCounts(notStarted = 2, recorded = 5).summary)
    }
    @Test fun blocksAreReportedInTheOrderTheUserMustFixThem() {
        val some = CatalogCounts(ready = 2)
        assertEquals(StartBlock.SERVICE, Preflight.block(false, false, false, CatalogCounts(recorded = 1)))
        assertEquals(StartBlock.LINE_MISSING, Preflight.block(true, false, false, some))
        assertEquals(StartBlock.OFFLINE, Preflight.block(true, true, false, some))
        assertEquals(StartBlock.NOTHING_READY, Preflight.block(true, true, true, CatalogCounts(notStarted = 4)))
        assertNull(Preflight.block(true, true, true, some))
    }
    @Test fun emptyCatalogIsNotABlockBecauseStartingSyncsFirst() {
        assertNull(Preflight.block(true, true, true, CatalogCounts()))
    }
}
