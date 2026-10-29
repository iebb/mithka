import Flutter
import UIKit

/// Flutter owns the app's split panes and embedded bottom tab row. Keep UIKit's
/// window-wide vertical bar adaptation from moving that row out of its host.
@objc(MithkaFlutterViewController)
final class MithkaFlutterViewController: FlutterViewController {
  @available(iOS 27.1, *)
  override var preferredVerticalBarBehavior: UIVerticalBarBehavior { .disabled }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for activity in connectionOptions.userActivities {
      if HandoffBridge.shared.accept(activity) { break }
    }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if !HandoffBridge.shared.accept(userActivity) {
      super.scene(scene, continue: userActivity)
    }
  }
}
