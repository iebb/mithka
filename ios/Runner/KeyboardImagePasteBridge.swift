import Flutter
import ObjectiveC
import UIKit

/// Sends images pasted into Flutter's iOS text field to the focused composer.
///
/// Flutter's text input view only pastes text: it disables Paste while the
/// pasteboard holds just an image, and its `paste:` ignores images. The iOS
/// keyboard still offers a copied screenshot as a "Photo" paste suggestion,
/// so tapping it did nothing. Image-only pastes are forwarded over
/// `mithka/keyboard_image_paste`; anything with text keeps Flutter's paste.
@MainActor
enum KeyboardImagePasteBridge {
  private static var channel: FlutterMethodChannel?
  private static var installed = false

  static func install(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "mithka/keyboard_image_paste",
      binaryMessenger: messenger
    )
    guard !installed, let textInputView = NSClassFromString("FlutterTextInputView") else {
      return
    }
    installed = true
    patchCanPerformAction(textInputView)
    patchPaste(textInputView)
  }

  /// The pasteboard's image, preferring the original GIF/PNG/JPEG bytes.
  static func pasteboardImage(_ pasteboard: UIPasteboard = .general) -> (data: Data, mimeType: String)? {
    for (type, mimeType) in [
      ("com.compuserve.gif", "image/gif"),
      ("public.png", "image/png"),
      ("public.jpeg", "image/jpeg"),
    ] {
      if let data = pasteboard.data(forPasteboardType: type), !data.isEmpty {
        return (data, mimeType)
      }
    }
    if let data = pasteboard.image?.pngData(), !data.isEmpty {
      return (data, "image/png")
    }
    return nil
  }

  private static func send(_ data: Data, mimeType: String) {
    channel?.invokeMethod(
      "pasteImage",
      arguments: ["data": FlutterStandardTypedData(bytes: data), "mimeType": mimeType]
    )
  }

  private static var pasteboardHasOnlyImages: Bool {
    let pasteboard = UIPasteboard.general
    return pasteboard.hasImages && !pasteboard.hasStrings
  }

  /// Patches only methods FlutterTextInputView defines itself, so a Flutter
  /// change can never redirect UIResponder's implementation for every view.
  private static func ownMethod(_ cls: AnyClass, _ selector: Selector) -> Method? {
    var count: UInt32 = 0
    guard let methods = class_copyMethodList(cls, &count) else { return nil }
    defer { free(methods) }
    return (0..<Int(count)).lazy.map { methods[$0] }.first { method_getName($0) == selector }
  }

  private typealias CanPerformAction = @convention(c) (AnyObject, Selector, Selector, Any?) -> Bool

  private static func patchCanPerformAction(_ cls: AnyClass) {
    let selector = #selector(UIResponder.canPerformAction(_:withSender:))
    guard let method = ownMethod(cls, selector) else { return }
    let original = unsafeBitCast(method_getImplementation(method), to: CanPerformAction.self)
    let replacement: @convention(block) (AnyObject, Selector, Any?) -> Bool = { view, action, sender in
      if original(view, selector, action, sender) { return true }
      return action == #selector(UIResponderStandardEditActions.paste(_:)) && pasteboardHasOnlyImages
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }

  private typealias Paste = @convention(c) (AnyObject, Selector, Any?) -> Void

  private static func patchPaste(_ cls: AnyClass) {
    let selector = #selector(UIResponderStandardEditActions.paste(_:))
    guard let method = ownMethod(cls, selector) else { return }
    let original = unsafeBitCast(method_getImplementation(method), to: Paste.self)
    let replacement: @convention(block) (AnyObject, Any?) -> Void = { view, sender in
      // Read inside the system paste so iOS does not ask for paste permission.
      if pasteboardHasOnlyImages, let image = pasteboardImage() {
        send(image.data, mimeType: image.mimeType)
      } else {
        original(view, selector, sender)
      }
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }
}
