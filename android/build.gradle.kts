allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// opencv_core (the OpenCV natives plugin) hardcodes compileSdk 33, but its
// androidx dependencies require ≥34 — force Android *library* subprojects up
// to the app's compileSdk so checkReleaseAarMetadata passes. (:app itself is
// an application module, not a LibraryExtension, so it's untouched.)
//
// Also align Java/Kotlin JVM targets to the app's (17): some plugins (e.g.
// tflite_flutter) default Java to 11 while their Kotlin compiles to 17, which
// fails :plugin:compileReleaseKotlin with an "Inconsistent JVM Target
// Compatibility" error. Forcing Java 17 here makes both consistent.
fun forceLibraryCompileSdk(p: Project) {
    p.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
        if ((compileSdk ?: 0) < 36) {
            compileSdk = 36
        }
        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
}
subprojects {
    if (state.executed) {
        forceLibraryCompileSdk(this)
    } else {
        afterEvaluate { forceLibraryCompileSdk(this) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
