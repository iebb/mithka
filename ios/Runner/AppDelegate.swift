import Flutter
import SwiftUI
import Translation
import UIKit

@main
@MainActor
@objc class AppDelegate: FlutterAppDelegate, @preconcurrency FlutterImplicitEngineDelegate {
  private var nativeTranslationBridge: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let clipboardChannel = FlutterMethodChannel(
      name: "mithka/clipboard",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "readImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = UIPasteboard.general
      if let data = pasteboard.data(forPasteboardType: "com.compuserve.gif") {
        result(["mimeType": "image/gif", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      if let data = pasteboard.data(forPasteboardType: "public.png") {
        result(["mimeType": "image/png", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      if let data = pasteboard.data(forPasteboardType: "public.jpeg") {
        result(["mimeType": "image/jpeg", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      if let image = pasteboard.image, let data = image.pngData() {
        result(["mimeType": "image/png", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      result(nil)
    }

    let nativeTranslationChannel = FlutterMethodChannel(
      name: "mithka/native_translation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    if #available(iOS 18.0, *) {
      let bridge = NativeTranslationBridge()
      nativeTranslationBridge = bridge
      bridge.attachHostIfNeeded()
      nativeTranslationChannel.setMethodCallHandler { call, result in
        if call.method == "capabilities" {
          result(["ios_system"])
          return
        }
        bridge.handle(call: call, result: result)
      }
    } else {
      nativeTranslationChannel.setMethodCallHandler { call, result in
        if call.method == "capabilities" {
          result([])
          return
        }
        guard call.method == "translate" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(
          FlutterError(
            code: "unsupported_platform",
            message: "本机翻译需要 iOS 18 或更高版本",
            details: nil
          )
        )
      }
    }
  }
}

@available(iOS 18.0, *)
@MainActor
private final class NativeTranslationBridge {
  private let coordinator = NativeTranslationCoordinator()
  private var hostController: UIHostingController<NativeTranslationHostView>?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "translate" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let text = args["text"] as? String,
      let targetLanguageCode = args["targetLanguageCode"] as? String,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !targetLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "缺少翻译文本或目标语言",
          details: nil
        )
      )
      return
    }

    attachHostIfNeeded()
    guard hostController != nil else {
      result(
        FlutterError(
          code: "translator_unavailable",
          message: "本机翻译暂不可用",
          details: nil
        )
      )
      return
    }

    coordinator.enqueue(
      text: text,
      sourceLanguageCode: args["sourceLanguageCode"] as? String,
      targetLanguageCode: targetLanguageCode,
      result: result
    )
  }

  func attachHostIfNeeded() {
    guard hostController == nil else { return }
    guard let root = Self.rootViewController() else { return }
    let host = UIHostingController(
      rootView: NativeTranslationHostView(coordinator: coordinator)
    )
    host.view.isHidden = true
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    root.addChild(host)
    root.view.addSubview(host.view)
    host.view.frame = .zero
    host.didMove(toParent: root)
    hostController = host
  }

  private static func rootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController
  }
}

@available(iOS 18.0, *)
private struct NativeTranslationHostView: View {
  @ObservedObject var coordinator: NativeTranslationCoordinator

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .translationTask(coordinator.configuration) { session in
        await coordinator.perform(session: session)
      }
  }
}

@available(iOS 18.0, *)
@MainActor
private final class NativeTranslationCoordinator: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?

  private var queue: [NativeTranslationRequest] = []
  private var activeRequestId: UUID?

  func enqueue(
    text: String,
    sourceLanguageCode: String?,
    targetLanguageCode: String,
    result: @escaping FlutterResult
  ) {
    queue.append(
      NativeTranslationRequest(
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        result: result
      )
    )
    startNextIfNeeded()
  }

  func perform(session: TranslationSession) async {
    guard
      let activeRequestId,
      let request = queue.first(where: { $0.id == activeRequestId })
    else { return }

    do {
      let response = try await session.translate(request.text)
      request.result(response.targetText)
    } catch {
      request.result(
        FlutterError(
          code: "translation_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }

    queue.removeAll { $0.id == activeRequestId }
    self.activeRequestId = nil
    configuration = nil
    if !queue.isEmpty {
      Task { @MainActor in
        self.startNextIfNeeded()
      }
    }
  }

  private func startNextIfNeeded() {
    guard activeRequestId == nil, let request = queue.first else { return }
    guard let target = Self.localeLanguage(for: request.targetLanguageCode) else {
      request.result(
        FlutterError(
          code: "unsupported_language",
          message: "不支持目标语言 \(request.targetLanguageCode)",
          details: nil
        )
      )
      queue.removeFirst()
      startNextIfNeeded()
      return
    }

    activeRequestId = request.id
    configuration = TranslationSession.Configuration(
      source: Self.localeLanguage(for: request.sourceLanguageCode),
      target: target
    )
  }

  private static func localeLanguage(for code: String?) -> Locale.Language? {
    guard
      let code,
      !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let normalized = code
      .replacingOccurrences(of: "_", with: "-")
      .lowercased()
    if normalized == "auto" || normalized == "autodetect" {
      return nil
    }
    if normalized == "zh" || normalized == "zh-hans" || normalized == "zh-cn" {
      return Locale.Language(identifier: "zh-Hans")
    }
    if normalized == "zh-hant" || normalized == "zh-tw" || normalized == "zh-hk" {
      return Locale.Language(identifier: "zh-Hant")
    }
    return Locale.Language(identifier: normalized.components(separatedBy: "-").first ?? normalized)
  }
}

private struct NativeTranslationRequest {
  let id = UUID()
  let text: String
  let sourceLanguageCode: String?
  let targetLanguageCode: String
  let result: FlutterResult
}
