import Flutter
import UIKit

/// A glass-surface-only platform view behind the app-owned tab row:
///
/// - On iOS 26+ the glass is the public `UIGlassEffect(style: .regular)` inside
///   a `UIVisualEffectView`, styled with `overrideUserInterfaceStyle` and
///   `tintColor` from the active theme.
/// - Before iOS 26 it uses a system material `UIBlurEffect`.
/// - The view draws no tabs, icons, or badges, and disables user interaction so
///   every tap lands on the Flutter tab controls above it.
@MainActor
final class NativeGlassSurfaceFactory: NSObject, FlutterPlatformViewFactory {
  private let registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeGlassSurface(frame: frame, id: viewId, registrar: registrar, arguments: args)
  }
}

@MainActor
private final class NativeGlassSurface: NSObject, FlutterPlatformView {
  private let host: GlassSurfaceHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, id: Int64, registrar: FlutterPluginRegistrar, arguments: Any?) {
    host = GlassSurfaceHost(frame: frame)
    channel = FlutterMethodChannel(
      name: "mithka/native_glass/\(id)", binaryMessenger: registrar.messenger()
    )
    super.init()
    if let configuration = arguments as? [String: Any] { host.apply(configuration) }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "update",
        let configuration = call.arguments as? [String: Any]
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.host.apply(configuration)
      result(nil)
    }
  }

  func view() -> UIView { host }

  deinit { channel.setMethodCallHandler(nil) }
}

@MainActor
private final class GlassSurfaceHost: UIView {
  private let effectView = UIVisualEffectView(effect: nil)
  private var requestedCornerRadius: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    effectView.isUserInteractionEnabled = false
    effectView.layer.masksToBounds = true
    addSubview(effectView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(_ configuration: [String: Any]) {
    let dark = configuration["dark"] as? Bool == true
    overrideUserInterfaceStyle = dark ? .dark : .light
    effectView.overrideUserInterfaceStyle = dark ? .dark : .light
    requestedCornerRadius = CGFloat((configuration["radius"] as? NSNumber)?.doubleValue ?? 0)
    setNeedsLayout()

    if #available(iOS 26.0, *) {
      var tint: UIColor?
      if let argb = configuration["tint"] as? NSNumber {
        let value = argb.uint32Value
        tint = UIColor(
          red: CGFloat((value >> 16) & 255) / 255,
          green: CGFloat((value >> 8) & 255) / 255,
          blue: CGFloat(value & 255) / 255,
          alpha: CGFloat((value >> 24) & 255) / 255
        )
      }
      // UIVisualEffectView copies its effect; mutating a retrieved effect does
      // not update the installed material. Configure before assigning it.
      let glass = UIGlassEffect(style: .regular)
      glass.tintColor = tint
      glass.isInteractive = false
      effectView.effect = glass
    } else {
      let desiredStyle: UIBlurEffect.Style = dark ? .systemMaterialDark : .systemMaterialLight
      effectView.effect = UIBlurEffect(style: desiredStyle)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.frame = bounds
    // Oversized CALayer radii can suppress the glass entirely. Resolve the
    // requested pill radius only after the platform view has its live bounds.
    effectView.layer.cornerRadius = min(
      max(0, requestedCornerRadius), min(bounds.width, bounds.height) / 2
    )
  }
}
