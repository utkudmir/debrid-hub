package com.utku.debridhub.shared.platform

import com.utku.debridhub.shared.domain.model.StoredAuthState
import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.ObjCObjectVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.pointed
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.CoreFoundation.CFDictionaryRef
import platform.CoreFoundation.CFRelease
import platform.CoreFoundation.kCFBooleanTrue
import platform.Foundation.CFBridgingRetain
import platform.Foundation.NSData
import platform.Foundation.NSMutableDictionary
import platform.Foundation.NSCopyingProtocol
import platform.Foundation.NSString
import platform.Foundation.NSStringEncoding
import platform.Foundation.NSUserDefaults
import platform.Foundation.create
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.SecItemUpdate
import platform.Security.errSecItemNotFound
import platform.Security.errSecSuccess
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
class SecureTokenStoreImpl(
    private val defaults: NSUserDefaults = NSUserDefaults.standardUserDefaults,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : SecureTokenStore {
    override suspend fun read(): StoredAuthState? = withContext(Dispatchers.Default) {
        readKeychainValue()?.let { stored ->
            decodeStoredAuthState(stored)?.let { return@withContext it }
            deleteKeychainValue()
        }

        migrateLegacyValueIfNeeded()
    }

    override suspend fun write(state: StoredAuthState) = withContext(Dispatchers.Default) {
        writeKeychainValue(json.encodeToString(state))
        defaults.removeObjectForKey(KEY_AUTH_STATE)
    }

    override suspend fun clear() = withContext(Dispatchers.Default) {
        deleteKeychainValue()
        defaults.removeObjectForKey(KEY_AUTH_STATE)
    }

    private fun migrateLegacyValueIfNeeded(): StoredAuthState? {
        val legacyValue = defaults.stringForKey(KEY_AUTH_STATE) ?: return null
        val state = decodeStoredAuthState(legacyValue)
        if (state == null) {
            defaults.removeObjectForKey(KEY_AUTH_STATE)
            return null
        }

        val migrated = runCatching {
            writeKeychainValue(legacyValue)
        }.isSuccess

        if (migrated) {
            defaults.removeObjectForKey(KEY_AUTH_STATE)
        }

        return state
    }

    private fun decodeStoredAuthState(raw: String): StoredAuthState? =
        runCatching { json.decodeFromString<StoredAuthState>(raw) }.getOrNull()

    private fun readKeychainValue(): String? = memScoped {
        withKeychainDictionary(
                kSecClass to kSecClassGenericPassword,
                kSecAttrService to KEYCHAIN_SERVICE,
                kSecAttrAccount to KEYCHAIN_ACCOUNT,
                kSecReturnData to kCFBooleanTrue,
                kSecMatchLimit to kSecMatchLimitOne
        ) { query ->
            val result = alloc<ObjCObjectVar<Any?>>()
            result.ptr.pointed.value = null
            val status = SecItemCopyMatching(query, result.ptr.reinterpret())
            when (status) {
                errSecSuccess -> (result.ptr.pointed.value as? NSData)?.toUtf8String()
                errSecItemNotFound -> null
                else -> throw IllegalStateException("Unable to read auth state from iOS Keychain (status=$status).")
            }
        }
    }

    private fun writeKeychainValue(raw: String) {
        val data = raw.toNSData()
        val updateStatus = withKeychainDictionary(
            kSecClass to kSecClassGenericPassword,
            kSecAttrService to KEYCHAIN_SERVICE,
            kSecAttrAccount to KEYCHAIN_ACCOUNT
        ) { identityQuery ->
            withKeychainDictionary(kSecValueData to data) { updatedValues ->
                SecItemUpdate(identityQuery, updatedValues)
            }
        }

        when (updateStatus) {
            errSecSuccess -> return
            errSecItemNotFound -> {
                val addStatus = withKeychainDictionary(
                    kSecClass to kSecClassGenericPassword,
                    kSecAttrService to KEYCHAIN_SERVICE,
                    kSecAttrAccount to KEYCHAIN_ACCOUNT,
                    kSecValueData to data
                ) { addQuery ->
                    SecItemAdd(addQuery, null)
                }
                if (addStatus != errSecSuccess) {
                    throw IllegalStateException("Unable to write auth state to iOS Keychain (status=$addStatus).")
                }
            }
            else -> throw IllegalStateException("Unable to update auth state in iOS Keychain (status=$updateStatus).")
        }
    }

    private fun deleteKeychainValue() {
        val status = withKeychainDictionary(
            kSecClass to kSecClassGenericPassword,
            kSecAttrService to KEYCHAIN_SERVICE,
            kSecAttrAccount to KEYCHAIN_ACCOUNT
        ) { identityQuery ->
            SecItemDelete(identityQuery)
        }
        if (status != errSecSuccess && status != errSecItemNotFound) {
            throw IllegalStateException("Unable to clear auth state from iOS Keychain (status=$status).")
        }
    }

    private companion object {
        const val KEY_AUTH_STATE = "auth_state_json"
        const val KEYCHAIN_SERVICE = "com.utku.debridhub.auth"
        const val KEYCHAIN_ACCOUNT = "stored_auth_state"
    }
}

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
private fun String.toNSData(): NSData {
    val bytes = encodeToByteArray()
    return bytes.usePinned {
        NSData.create(bytes = it.addressOf(0), length = bytes.size.toULong())
    }
}

@OptIn(BetaInteropApi::class)
private fun NSData.toUtf8String(): String? =
    NSString.create(data = this, encoding = NS_UTF8_ENCODING)?.toString()

private const val NS_UTF8_ENCODING: NSStringEncoding = 4u

@OptIn(ExperimentalForeignApi::class)
private fun keychainDictionary(vararg entries: Pair<Any?, Any?>): NSMutableDictionary {
    val dictionary = NSMutableDictionary()
    entries.forEach { (key, value) ->
        val dictionaryKey = key as? NSCopyingProtocol ?: return@forEach
        val dictionaryValue = value ?: return@forEach
        dictionary.setObject(dictionaryValue, forKey = dictionaryKey)
    }
    return dictionary
}

@OptIn(ExperimentalForeignApi::class)
private inline fun <T> withKeychainDictionary(
    vararg entries: Pair<Any?, Any?>,
    block: (CFDictionaryRef) -> T
): T {
    val retainedDictionary = CFBridgingRetain(keychainDictionary(*entries))
        ?: throw IllegalStateException("Unable to bridge iOS dictionary for Keychain access.")
    return try {
        block(retainedDictionary.reinterpret())
    } finally {
        CFRelease(retainedDictionary)
    }
}
