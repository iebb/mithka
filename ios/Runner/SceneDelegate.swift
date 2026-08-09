import Flutter
import UIKit

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
