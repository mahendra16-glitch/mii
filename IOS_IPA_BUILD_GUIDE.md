# Flutter iOS Unsigned IPA Build Guide (GitHub Actions)

This guide documents the exact GitHub Actions workflow and dependency adjustments required to automatically build and export an unsigned `.ipa` file for Flutter apps.

---

## 1. GitHub Actions Workflow File

Create `.github/workflows/build_ios.yml` in your target repository:

```yaml
name: Build iOS IPA

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build-ios:
    name: Build iOS App (.ipa)
    runs-on: macos-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.4'
          channel: 'stable'
          cache: true

      - name: Install Dependencies
        run: |
          flutter pub get
          cd ios
          pod install
          cd ..

      - name: Build Unsigned IPA
        run: |
          flutter build ipa --release --no-codesign
          mkdir -p "$GITHUB_WORKSPACE/build/ios/ipa"
          if [ -d "$GITHUB_WORKSPACE/build/ios/archive/Runner.xcarchive/Products/Applications" ]; then
            cd "$GITHUB_WORKSPACE/build/ios/archive/Runner.xcarchive/Products/Applications"
            mkdir -p Payload
            cp -r Runner.app Payload/
            zip -r "$GITHUB_WORKSPACE/build/ios/ipa/YourApp_Unsigned.ipa" Payload
          fi

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: YourApp_iOS_IPA
          path: |
            build/ios/ipa/*.ipa
            build/ios/archive/Runner.xcarchive
          retention-days: 7
```

---

## 2. Key Workflow Steps Explained

1. **Flutter Version Selection (`3.27.4`)**:
   - Flutter 3.27.4 uses Dart SDK 3.6.2.
   - Prevents `The current Dart SDK version is 3.4.4` errors (from older Flutter runner defaults).
   - Avoids Flutter 3.29 breaking API changes (`IconData` marked as final, `TooltipPositionDelegate` conflict in `super_tooltip`).

2. **Unsigned IPA Build Command**:
   - `flutter build ipa --release --no-codesign` archives the project into `build/ios/archive/Runner.xcarchive`.

3. **Packaging `Runner.app` into `.ipa`**:
   - An iOS `.ipa` file is a ZIP archive containing a `Payload/` folder with `Runner.app` inside.
   - The workflow script creates a `Payload/` directory inside `Runner.xcarchive/Products/Applications`, copies `Runner.app` into it, and zips it into `$GITHUB_WORKSPACE/build/ios/ipa/YourApp_Unsigned.ipa`.

4. **Artifact Upload**:
   - Uses `actions/upload-artifact@v4` to upload the zipped `.ipa` file so you can download it directly from the GitHub Actions **Summary** page.

---

## 3. Recommended `pubspec.yaml` Dependency Ranges

To prevent version resolution failures across Flutter 3.27 and Dart 3.6, ensure package versions use ranges instead of rigid caret pins:

```yaml
dependencies:
  intl: '>=0.19.0 <0.21.0'
  upgrader: '>=10.0.0 <12.0.0'
  image_picker: '>=1.0.0 <1.3.0'

dependency_overrides:
  sqflite: '>=2.3.0 <2.4.0'
```

---

## 4. How to Apply to Other Projects

1. Copy `.github/workflows/build_ios.yml` to your target Flutter project's `.github/workflows/` directory.
2. Change `YourApp_Unsigned.ipa` and `YourApp_iOS_IPA` in the YAML file to match your app's name.
3. Commit and push to `main` or `master`.
4. Navigate to **Actions** -> **Build iOS App (.ipa)** -> **Summary** -> **Artifacts** to download your unsigned `.ipa`.
