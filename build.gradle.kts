plugins {
    id("org.jetbrains.kotlin.multiplatform") apply false
    id("org.jetbrains.kotlin.plugin.compose") apply false
    id("org.jetbrains.kotlin.plugin.serialization") apply false
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("com.android.kotlin.multiplatform.library") apply false
    id("io.gitlab.arturbosch.detekt") version "1.23.8" apply false
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
