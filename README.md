# JalanGo Android APK Builder

This project contains the JalanGo Flutter starter and a GitHub Actions workflow that builds a release APK in the cloud. It does **not** contain a prebuilt APK yet.

## Build using an Android phone

1. Sign in to GitHub in your phone browser and create a **new private repository** named `JalanGo`.
2. On the repository page, choose **Add file → Upload files**. Upload the *contents* of this folder (especially `lib/`, `pubspec.yaml`, and `.github/workflows/build-apk.yml`) so `pubspec.yaml` is at the repository root. If the mobile site does not show the upload option, open the browser menu and enable **Desktop site**.
3. Commit the uploaded files to the `main` branch.
4. Open the repository's **Actions** tab. Select **Build JalanGo Android APK** and press **Run workflow** if it did not start automatically after the commit.
5. Wait for the workflow to finish successfully. Open that completed run, scroll to **Artifacts**, and download `JalanGo-Android-APK`.
6. Extract the downloaded artifact ZIP to obtain `app-release.apk`, then tap the APK to install. Android may ask you to allow installs from that browser or file manager. Only allow this for files you trust.

## Prototype limitations

- This is an early prototype, not a production navigation app.
- Search uses the public Nominatim geocoder and routing uses the public OSRM demo server. They are best-effort prototype services, not guaranteed for public commercial traffic.
- Road reports are local demo selections only; they are not shared with other users.
- No voice turn-by-turn navigation or live traffic feed is implemented yet.
- The workflow builds an unsigned APK for personal testing. Public Play Store release needs further testing, policy review, and a properly signed Android App Bundle.
