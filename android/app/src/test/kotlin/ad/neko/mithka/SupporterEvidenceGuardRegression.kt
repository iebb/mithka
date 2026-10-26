package ad.neko.mithka

/**
 * Dependency-free regression entry point: compile with the pure
 * SupporterEvidenceGuard class from MithkaProPlugin.kt, then run this object.
 * No Android runtime, JUnit dependency, store connection or wall-clock waits.
 */
object SupporterEvidenceGuardRegression {
    @JvmStatic
    fun main(args: Array<String>) {
        freshQueryAllows()
        delayedQueryAfterInvalidationDenies()
        queuedSetterAfterInvalidationDenies()
        delayedAcknowledgementCannotRestoreAuthority()
        pauseResumeRequiresNewEvidence()
        overlappingEmptyThenActiveQueriesAreIndependent()
        overlappingActiveThenEmptyQueriesDenyOldEvidence()
        println("PASS: 7 native supporter epoch/query regressions")
    }

    private fun foregroundGuard() = SupporterEvidenceGuard().apply {
        setForeground(true)
    }

    private fun freshQueryAllows() {
        val guard = foregroundGuard()
        val evidence = guard.complete(guard.beginQuery(), true, true)
        var writes = 0
        check(guard.withActiveEvidence(evidence) { writes++; true })
        check(writes == 1 && guard.cachedActive())
    }

    private fun delayedQueryAfterInvalidationDenies() {
        val guard = foregroundGuard()
        val ticket = guard.beginQuery()
        guard.invalidate() // Purchase update/disconnect before query callback.
        val evidence = guard.complete(ticket, true, true)
        check(!guard.withActiveEvidence(evidence) { error("Stale query changed alias") })
        check(!guard.cachedActive())
    }

    private fun queuedSetterAfterInvalidationDenies() {
        val guard = foregroundGuard()
        val evidence = guard.complete(guard.beginQuery(), true, true)
        guard.invalidate() // Callback was posted, but UI setter has not run yet.
        check(!guard.withActiveEvidence(evidence) { error("Queued stale setter ran") })
    }

    private fun delayedAcknowledgementCannotRestoreAuthority() {
        val guard = foregroundGuard()
        val evidence = guard.complete(guard.beginQuery(), true, true)
        val acknowledgeCompletion = {
            guard.withActiveEvidence(evidence) { error("Ack restored stale authority") }
        }
        guard.invalidate()
        check(!acknowledgeCompletion())
        check(!guard.cachedActive())
    }

    private fun pauseResumeRequiresNewEvidence() {
        val guard = foregroundGuard()
        val old = guard.complete(guard.beginQuery(), true, true)
        guard.setForeground(false)
        check(!guard.withActiveEvidence(old) { error("Background setter ran") })
        guard.setForeground(true)
        check(!guard.withActiveEvidence(old) { error("Resume revived old evidence") })
        val fresh = guard.complete(guard.beginQuery(), true, true)
        check(guard.withActiveEvidence(fresh) { true })
    }

    private fun overlappingEmptyThenActiveQueriesAreIndependent() {
        val guard = foregroundGuard()
        val older = guard.beginQuery()
        val newer = guard.beginQuery()
        val active = guard.complete(newer, true, true)
        val empty = guard.complete(older, false, true)
        check(!empty.active && active.active) // Immutable per-query getState answer.
        check(guard.cachedActive()) // Older empty callback cannot clobber newer active.
        check(guard.withActiveEvidence(active) { true })
    }

    private fun overlappingActiveThenEmptyQueriesDenyOldEvidence() {
        val guard = foregroundGuard()
        val older = guard.beginQuery()
        val newer = guard.beginQuery()
        val empty = guard.complete(newer, false, true)
        val oldActive = guard.complete(older, true, true)
        check(!empty.active && oldActive.active)
        check(!guard.cachedActive())
        check(!guard.withActiveEvidence(oldActive) { error("Old active callback won") })
    }
}
