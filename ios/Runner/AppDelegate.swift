import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let appInfo = FlutterMethodChannel(
      name: "com.paypr.app/app_info",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appInfo.setMethodCallHandler { call, result in
      guard call.method == "getVersion" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      result(version.map { version in build.map { "\(version) (\($0))" } ?? version })
    }
  }
}
