# ledger_pulse

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android release packages

For direct installs, build one APK per CPU architecture. The APKs are written to
`build/app/outputs/flutter-apk/`.

```sh
flutter build apk --release --split-per-abi
```

For Google Play, build an Android App Bundle so Play can deliver the appropriate
native libraries to each device.

```sh
flutter build appbundle --release
```
