allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Some plugins (e.g. file_picker) pin an older compileSdk than newer transitive
// deps (flutter_plugin_android_lifecycle) require. Force every Android subproject
// to compileSdk 36. Registered first — before the evaluationDependsOn block below
// triggers evaluation — so the afterEvaluate hook lands before each subproject is
// evaluated. Reflection avoids a compile-time AGP dependency on the root script.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            android.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(android, 36)
        }
    }
}

// fvp 0.37.2 calls MDK_setGlobalOptionInt32("profiler.gpu", 1) from
// JNI_OnLoad. On Android 14/15 devices that can abort the process while
// System.loadLibrary("fvp") initializes, before Dart can configure fvp. Keep
// fvp enabled, but remove that optional profiler switch before native build.
subprojects {
    if (name == "fvp") {
        tasks.matching { it.name == "preBuild" }.configureEach {
            doFirst {
                val source = file("fvp_plugin.cpp")
                if (!source.exists()) return@doFirst
                val original = source.readText()
                val patched = original.replace(
                    "    mdk::SetGlobalOption(\"profiler.gpu\", 1);\n\n",
                    "    // Disabled by Mithka: crashes inside MDK on Android 14/15 during library load.\n",
                )
                if (patched != original) {
                    source.writeText(patched)
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
