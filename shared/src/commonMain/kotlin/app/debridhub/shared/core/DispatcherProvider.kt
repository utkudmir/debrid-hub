package app.debridhub.shared.core

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * Abstraction over coroutine dispatchers to allow deterministic testing and
 * platform‑specific optimisations.  Inject this into your use‑cases rather
 * than hard‑coding [Dispatchers.IO] or [Dispatchers.Default].
 */
interface DispatcherProvider {
    val io: CoroutineDispatcher
    val default: CoroutineDispatcher
    val main: CoroutineDispatcher
}

/**
 * Default implementation used in production.  On Android and iOS the
 * dispatchers resolve to the KotlinX `Dispatchers` singletons.  When unit
 * testing you can provide a test implementation to ensure deterministic
 * execution.
 */
object DefaultDispatcherProvider : DispatcherProvider {
    override val io: CoroutineDispatcher = Dispatchers.Default
    override val default: CoroutineDispatcher = Dispatchers.Default
    override val main: CoroutineDispatcher = Dispatchers.Default
}
