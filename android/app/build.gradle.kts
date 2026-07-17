plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Wczytaj key.properties (plik lokalny, nie w git)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = java.util.Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace  = "com.dynomic.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias      = keystoreProperties["KEY_ALIAS"]      as String
            keyPassword   = keystoreProperties["KEY_PASSWORD"]   as String
            storeFile     = file(keystoreProperties["STORE_FILE"] as String)
            storePassword = keystoreProperties["STORE_PASSWORD"] as String
        }
    }

    defaultConfig {
        applicationId = "com.dynomic.app"
        minSdk        = flutter.minSdkVersion
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig   = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}