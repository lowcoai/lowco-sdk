import com.vanniktech.maven.publish.AndroidSingleVariantLibrary
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library") version "8.11.1"
    id("org.jetbrains.kotlin.android") version "2.2.20"
    // 0.36+ needs Gradle 9 and AGP 8.13.
    id("com.vanniktech.maven.publish") version "0.35.0"
    signing
}

group = "ai.lowco"
version = "0.1.0"

android {
    namespace = "ai.lowco.engage"
    compileSdk = 35

    defaultConfig {
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    // Android's org.json is a stub in local unit tests; the JVM tests use the real one.
    testImplementation("org.json:json:20240303")
}

// Maven Central credentials and signing keys come from user Gradle properties or environment variables.
mavenPublishing {
    configure(AndroidSingleVariantLibrary(variant = "release", sourcesJar = true, publishJavadocJar = true))
    coordinates(group.toString(), "engage", version.toString())
    publishToMavenCentral()
    signAllPublications()

    pom {
        name.set("lowco engage")
        description.set("Android analytics SDK for the lowco engage service: events, screen views, sessions and deep-link attribution.")
        inceptionYear.set("2026")
        url.set("https://github.com/lowcoai/lowco-sdk")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("lowcoai")
                name.set("Lowco AI")
                url.set("https://lowco.ai")
                organization.set("Lowco AI")
                organizationUrl.set("https://lowco.ai")
            }
        }
        scm {
            url.set("https://github.com/lowcoai/lowco-sdk/tree/main/android/engage")
            connection.set("scm:git:https://github.com/lowcoai/lowco-sdk.git")
            developerConnection.set("scm:git:ssh://git@github.com/lowcoai/lowco-sdk.git")
        }
    }
}

// signAllPublications() requires a key for every release version. Require it only for uploads to Central, so
// publishToMavenLocal works without one (and still signs when a key is configured).
signing {
    setRequired(provider { gradle.taskGraph.hasTask(":publishAllPublicationsToMavenCentralRepository") })
}
