package com.utku.debridhub.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.window.WindowInsets
import androidx.compose.ui.window.WindowInsetsSides
import androidx.compose.ui.window.WindowInsetsType
import androidx.compose.ui.window.rememberWindowInsetsController
import com.utku.debridhub.compose.ui.HomeScreen
import com.utku.debridhub.compose.ui.OnboardingScreen
import com.utku.debridhub.compose.ui.theme.AppTheme
// import com.utku.debridhub.shared.domain.model.ExpiryState
// import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.repository.AuthRepository
import com.utku.debridhub.shared.domain.repository.AccountRepository
import kotlinx.coroutines.launch

/**
 * Entry point composable for the application.  This function decides which
 * screen to display based on authentication state.  If the user has not
 * connected their Real‑Debrid account yet then the onboarding flow is
 * presented.  Otherwise the home screen is shown.  All screens are wrapped
 * in [AppTheme] to apply a consistent Material theme.
 */
@Composable
fun App(
    authRepository: AuthRepository,
    accountRepository: AccountRepository,
    onConnectRequested: () -> Unit,
    onRequestNotificationPermission: () -> Unit
) {
    AppTheme {
        // Maintain local state that determines whether the user is authenticated.
        val isAuthenticatedState = remember { mutableStateOf(false) }

        // Check authentication on first composition.  Because
        // [AuthRepository.isAuthenticated] is suspending we call it in a
        // coroutine and update the state when complete.
        LaunchedEffect(Unit) {
            isAuthenticatedState.value = authRepository.isAuthenticated()
        }

        if (!isAuthenticatedState.value) {
            val scope = androidx.compose.runtime.rememberCoroutineScope()
            OnboardingScreen(
                onConnect = {
                    scope.launch {
                        onConnectRequested()
                        // Recheck authentication state after user completes auth.
                        isAuthenticatedState.value = authRepository.isAuthenticated()
                    }
                },
                onRequestNotificationPermission = onRequestNotificationPermission
            )
        } else {
            HomeScreen(accountRepository = accountRepository)
        }
    }
}