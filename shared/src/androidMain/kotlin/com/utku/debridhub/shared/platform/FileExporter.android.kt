package com.utku.debridhub.shared.platform

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class FileExporterImpl(
    private val context: Context
) : FileExporter {
    override suspend fun exportTextFile(fileName: String, content: String): ExportedFile = withContext(Dispatchers.IO) {
        val exportDir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(exportDir, fileName)
        file.writeText(content)
        ExportedFile(
            displayName = file.name,
            location = file.absolutePath
        )
    }
}
