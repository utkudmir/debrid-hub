package com.utku.debridhub.shared.platform

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import platform.Foundation.NSData
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.create
import platform.Foundation.writeToFile

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
class FileExporterImpl : FileExporter {
    override suspend fun exportTextFile(fileName: String, content: String): ExportedFile = withContext(Dispatchers.Default) {
        val path = NSTemporaryDirectory() + fileName
        content.encodeToByteArray().toNSData().writeToFile(path, atomically = true)
        ExportedFile(
            displayName = fileName,
            location = path
        )
    }
}

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
private fun ByteArray.toNSData(): NSData = usePinned {
    NSData.create(bytes = it.addressOf(0), length = size.toULong())
}
