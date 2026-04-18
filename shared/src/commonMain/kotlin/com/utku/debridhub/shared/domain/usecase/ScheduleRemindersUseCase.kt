package com.utku.debridhub.shared.domain.usecase

import com.utku.debridhub.shared.domain.model.ScheduledReminder
import com.utku.debridhub.shared.domain.repository.AccountRepository
import com.utku.debridhub.shared.domain.repository.ReminderRepository

class ScheduleRemindersUseCase(
    private val accountRepository: AccountRepository,
    private val reminderRepository: ReminderRepository
) {
    suspend operator fun invoke(): Result<List<ScheduledReminder>> {
        return accountRepository.refreshAccountStatus().mapCatching { status ->
            reminderRepository.scheduleReminders(status)
        }
    }
}
