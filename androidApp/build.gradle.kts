import org.gradle.api.tasks.testing.Test
import org.gradle.testing.jacoco.plugins.JacocoTaskExtension
import org.gradle.testing.jacoco.tasks.JacocoCoverageVerification
import org.gradle.testing.jacoco.tasks.JacocoReport
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    jacoco
}

android {
    namespace = "app.debridhub.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.debridhub"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    buildFeatures {
        buildConfig = true
        compose = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_21)
    }
}

jacoco {
    toolVersion = "0.8.12"
}

tasks.withType<Test>().configureEach {
    outputs.upToDateWhen { false }
    doFirst {
        delete(layout.buildDirectory.dir("test-results/$name/binary"))
    }
    extensions.configure(JacocoTaskExtension::class.java) {
        isIncludeNoLocationClasses = true
        excludes = listOf("jdk.internal.*")
    }
}

val coverageClassExcludes = listOf(
    "**/*$*",
    "**/AndroidAppGraph*",
    "**/ComposableSingletons*",
    "**/DebridHubAppKt*",
    "**/DebridHubViewModelFactory*",
    "**/MainActivity*",
    "**/domain/model/**",
    "**/domain/repository/**",
    "**/platform/**",
    "**/DispatcherProvider*"
)

val androidClassesJar = layout.buildDirectory.file("intermediates/runtime_app_classes_jar/debug/bundleDebugClassesToRuntimeJar/classes.jar")
val sharedClassesJar = project(":shared").layout.buildDirectory.file("intermediates/runtime_library_classes_jar/androidMain/bundleAndroidMainClassesToRuntimeJar/classes.jar")
val sharedSourcesDir = project(":shared").projectDir.resolve("src/commonMain/kotlin")

val prepareCoverageArtifacts by tasks.registering(Delete::class) {
    delete(
        layout.buildDirectory.file("jacoco/testDebugUnitTest.exec"),
        layout.buildDirectory.dir("reports/jacoco/jacocoDebugUnitTestReport")
    )
}

tasks.register<JacocoReport>("jacocoDebugUnitTestReport") {
    dependsOn(prepareCoverageArtifacts, "testDebugUnitTest")

    reports {
        xml.required.set(true)
        html.required.set(true)
    }

    classDirectories.setFrom(
        files(
            androidClassesJar.map { zipTree(it.asFile) },
            sharedClassesJar.map { zipTree(it.asFile) }
        ).asFileTree.matching {
            exclude(coverageClassExcludes)
        }
    )
    sourceDirectories.setFrom(files(projectDir.resolve("src/main/java"), sharedSourcesDir))
    executionData.setFrom(
        fileTree(layout.buildDirectory) {
            include("jacoco/testDebugUnitTest.exec")
            include("outputs/unit_test_code_coverage/debugUnitTest/testDebugUnitTest.exec")
        }
    )
}

tasks.register<JacocoCoverageVerification>("jacocoDebugUnitTestCoverageVerification") {
    dependsOn("jacocoDebugUnitTestReport")

    classDirectories.setFrom(
        files(
            androidClassesJar.map { zipTree(it.asFile) },
            sharedClassesJar.map { zipTree(it.asFile) }
        ).asFileTree.matching {
            exclude(coverageClassExcludes)
        }
    )
    sourceDirectories.setFrom(files(projectDir.resolve("src/main/java"), sharedSourcesDir))
    executionData.setFrom(
        fileTree(layout.buildDirectory) {
            include("jacoco/testDebugUnitTest.exec")
            include("outputs/unit_test_code_coverage/debugUnitTest/testDebugUnitTest.exec")
        }
    )

    violationRules {
        rule {
            limit {
                counter = "LINE"
                value = "COVEREDRATIO"
                minimum = "0.70".toBigDecimal()
            }
        }
        rule {
            limit {
                counter = "BRANCH"
                value = "COVEREDRATIO"
                minimum = "0.55".toBigDecimal()
            }
        }
    }
}

dependencies {
    implementation(project(":shared"))

    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")

    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.runtime:runtime")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.10.0")
    implementation("com.google.android.material:material:1.13.0")
    implementation("io.ktor:ktor-client-content-negotiation:3.4.2")
    implementation("io.ktor:ktor-client-logging:3.4.2")
    implementation("io.ktor:ktor-client-okhttp:3.4.2")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.4.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation(kotlin("test"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("io.ktor:ktor-client-mock:3.4.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")

    androidTestImplementation("androidx.test:core-ktx:1.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
