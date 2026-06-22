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
