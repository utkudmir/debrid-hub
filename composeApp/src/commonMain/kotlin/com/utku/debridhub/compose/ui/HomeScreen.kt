package com.utku.debridhub.compose.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.ExpiryState
import com.utku.debridhub.shared.domain.repository.AccountRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Displays the user’s current Real‑Debrid account status and remaining
 * subscription time.  This composable queries the [AccountRepository] when
 * first composed and shows a simple card with the username, days remaining
 * and expiry state.  Any errors are surfaced via fallback text.
 */
@Composable
fun HomeScreen(accountRepository: AccountRepository) {
    val statusState = remember { mutableStateOf<AccountStatus?>(null) }
    val errorState = remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        val result = withContext(Dispatchers.Default) {
            accountRepository.refreshAccountStatus()
        }
        result.onSuccess { status ->
            statusState.value = status
        }
        result.onFailure { throwable ->
            errorState.value = throwable.message
        }
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.padding(16.dp)
    ) {
        when {
            statusState.value != null -> {
                val status = statusState.value!!
                // Derive a human‑readable state based on premium status and remaining days.
                val stateLabel = when {
                    !status.isPremium -> "Expired"
                    status.remainingDays == null -> "Unknown"
                    status.remainingDays > 7 -> "Active"
                    status.remainingDays in 1..7 -> "Expiring soon"
                    status.remainingDays <= 0 -> "Expired"
                    else -> "Active"
                }
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "Username: ${status.username ?: "Unknown"}",
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            text = "Days remaining: ${status.remainingDays ?: "–"}",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            text = "Status: $stateLabel",
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
            errorState.value != null -> {
                Text(text = errorState.value!!, color = MaterialTheme.colorScheme.error)
            }
            else -> {
                Text(text = "Loading account status…")
            }
        }
    }
}