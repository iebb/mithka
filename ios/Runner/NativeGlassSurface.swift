import Flutter
import UIKit

/// A glass-surface-only platform view behind the app-owned tab row:
///
/// - On iOS 26+ the glass is the public `UIGlassEffect(style: .regular)` inside
///   a `UIVisualEffectView`, styled with `overrideUserInterfaceStyle` and
///   `tintColor` from the active theme. The selected effect is nested in the
///   outer effect's contentView, as documented in WWDC25/284 at 21:02.
///   Do not make them siblings in UIGlassContainerEffect: overlapping effects
///   there merge into one shape, losing the distinct selection.
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
final class GlassSurfaceHost: UIView {
  private let effectView = UIVisualEffectView(effect: nil)
  private let selectionView = UIVisualEffectView(effect: nil)
  private var configuration: [String: Any] = [:]
  private var requestedCornerRadius: CGFloat = 0
  private var selection = -1
  private var itemCount = 0
  private var inset: CGFloat = 5
  private var rtl = false
  private var duration: TimeInterval = 0
  private var lastBounds: CGRect = .null
  private var animateSelection = false
  private var selectionAnimator: UIViewPropertyAnimator?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    for view in [effectView, selectionView] {
      view.isUserInteractionEnabled = false
      view.layer.masksToBounds = true
    }
    addSubview(effectView)
    // Public UIKit nested-glass hierarchy, not a second Flutter platform view
    // and not a merging UIGlassContainerEffect of overlapping sibling shapes.
    effectView.contentView.addSubview(selectionView)
    for name in [
      UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
      UIAccessibility.reduceMotionStatusDidChangeNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(accessibilityChanged), name: name, object: nil
      )
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { NotificationCenter.default.removeObserver(self) }

  func apply(_ configuration: [String: Any]) {
    // Resolve any previous pending layout before deciding whether the next move
    // is a selection change (animate) or a geometry change (snap).
    layoutIfNeeded()
    let nextSelection = (configuration["selection"] as? NSNumber)?.intValue ?? -1
    let nextCount = max(0, (configuration["itemCount"] as? NSNumber)?.intValue ?? 0)
    let nextInset = max(0, number(configuration, "selectionInset", fallback: 5))
    let nextRTL = configuration["rtl"] as? Bool == true
    animateSelection = selection >= 0 && nextSelection != selection &&
      nextCount == itemCount && nextInset == inset && nextRTL == rtl
    selection = nextSelection
    itemCount = nextCount
    inset = nextInset
    rtl = nextRTL
    duration = max(0, Double(number(configuration, "durationMs"))) / 1000
    requestedCornerRadius = number(configuration, "radius")
    let appearanceKeys = [
      "dark", "tint", "selectionTint", "opaqueBackground", "opaqueSelection",
      "contrastBorder", "highContrast",
    ]
    let appearanceChanged = appearanceKeys.contains {
      !NSObject.isEqualValue(self.configuration[$0], configuration[$0])
    }
    self.configuration = configuration
    if appearanceChanged { updateEffects() }
    setNeedsLayout()
    layoutIfNeeded()
  }

  private func number(
    _ configuration: [String: Any], _ key: String, fallback: CGFloat = 0
  ) -> CGFloat {
    let value = CGFloat((configuration[key] as? NSNumber)?.doubleValue ?? Double(fallback))
    return value.isFinite ? value : fallback
  }

  private func color(_ key: String, fallback: UIColor) -> UIColor {
    guard let argb = configuration[key] as? NSNumber else { return fallback }
    let value = argb.uint32Value
    return UIColor(
      red: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255,
      alpha: CGFloat((value >> 24) & 255) / 255
    )
  }

  @objc private func accessibilityChanged() {
    updateEffects()
    animateSelection = false
    setNeedsLayout()
    layoutIfNeeded()
  }

  private func updateEffects() {
    let dark = configuration["dark"] as? Bool == true
    overrideUserInterfaceStyle = dark ? .dark : .light
    let opaque = configuration["highContrast"] as? Bool == true ||
      UIAccessibility.isReduceTransparencyEnabled || UIAccessibility.isDarkerSystemColorsEnabled
    for (view, tintKey, opaqueKey) in [
      (effectView, "tint", "opaqueBackground"),
      (selectionView, "selectionTint", "opaqueSelection"),
    ] {
      view.overrideUserInterfaceStyle = overrideUserInterfaceStyle
      view.backgroundColor = opaque ? color(opaqueKey, fallback: .systemBackground) : .clear
      view.contentView.backgroundColor = .clear
      if opaque {
        view.effect = nil
      } else if #available(iOS 26.0, *) {
        // UIVisualEffectView copies effects. Configure a NEW effect before
        // assignment on both layers, including live theme/tint changes.
        let glass = UIGlassEffect(style: .regular)
        glass.tintColor = color(tintKey, fallback: .clear)
        glass.isInteractive = false
        view.effect = glass
      } else {
        view.effect = UIBlurEffect(style: dark ? .systemMaterialDark : .systemMaterialLight)
        if view === selectionView {
          view.contentView.backgroundColor = color("selectionTint", fallback: .clear)
        }
      }
    }
    selectionView.layer.borderWidth = opaque ? 1 : 0
    selectionView.layer.borderColor = color("contrastBorder", fallback: .label).cgColor
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let resized = lastBounds != bounds
    lastBounds = bounds
    effectView.frame = bounds
    // Oversized CALayer radii can suppress glass entirely. Clamp EACH effect
    // to its OWN live bounds, including the narrower selected capsule.
    effectView.layer.cornerRadius = min(
      max(0, requestedCornerRadius), max(0, min(bounds.width, bounds.height) / 2)
    )
    let hasSelection = itemCount > 0 && selection >= 0 && selection < itemCount
    selectionView.isHidden = !hasSelection
    let inner = bounds.insetBy(
      dx: min(inset, max(0, bounds.width / 2)),
      dy: min(inset, max(0, bounds.height / 2))
    )
    let width = hasSelection ? inner.width / CGFloat(itemCount) : 0
    let slot = rtl ? itemCount - 1 - selection : selection
    let target = CGRect(
      x: inner.minX + CGFloat(hasSelection ? slot : 0) * width,
      y: inner.minY, width: width, height: inner.height
    )
    let shouldAnimate = animateSelection && !resized && hasSelection && duration > 0 &&
      !UIAccessibility.isReduceMotionEnabled
    animateSelection = false
    // A dependency-only rebuild must not stop an in-flight move. Geometry,
    // accessibility and duration=0 changes, however, snap to the latest target.
    if shouldAnimate || resized || !hasSelection || duration == 0 ||
      UIAccessibility.isReduceMotionEnabled || selectionView.frame != target {
      stopSelectionAnimation()
      selectionView.layer.cornerRadius = min(
        max(0, requestedCornerRadius), max(0, min(target.width, target.height) / 2)
      )
      if shouldAnimate {
        let timing = UICubicTimingParameters(
          controlPoint1: CGPoint(x: 0.05, y: 0.70),
          controlPoint2: CGPoint(x: 0.10, y: 1.0)
        )
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations { self.selectionView.frame = target }
        selectionAnimator = animator
        animator.startAnimation()
      } else {
        UIView.performWithoutAnimation { self.selectionView.frame = target }
      }
    }
  }

  private func stopSelectionAnimation() {
    if let animator = selectionAnimator, animator.state == .active {
      // Finish at the presentation position, not the previous model target:
      // rapid taps reverse smoothly rather than jumping to the old endpoint.
      animator.stopAnimation(false)
      animator.finishAnimation(at: .current)
    }
    selectionAnimator = nil
  }
}

private extension NSObject {
  static func isEqualValue(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case let (lhs as NSObject, rhs as NSObject): return lhs.isEqual(rhs)
    default: return false
    }
  }
}

/// Actual system tab control, separate from the generic, noninteractive glass
/// surface above. No custom glass layers, selected capsule, or badge gestures.
@MainActor
final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBarPlatformView(frame: frame, id: viewId, registrar: registrar, arguments: args)
  }
}

@MainActor
private final class NativeTabBarPlatformView: NSObject, FlutterPlatformView {
  private let host: NativeTabBarHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, id: Int64, registrar: FlutterPluginRegistrar, arguments: Any?) {
    host = NativeTabBarHost(frame: frame)
    channel = FlutterMethodChannel(
      name: "mithka/native_tab_bar/\(id)", binaryMessenger: registrar.messenger()
    )
    super.init()
    host.onSelect = { [weak self] id in
      self?.channel.invokeMethod("select", arguments: ["id": id])
    }
    host.onMarkAllRead = { [weak self] id, epoch in
      self?.channel.invokeMethod("markAllRead", arguments: ["id": id, "actionEpoch": epoch])
    }
    host.onMetrics = { [weak self] metrics in
      self?.channel.invokeMethod("metrics", arguments: metrics)
    }
    if let configuration = arguments as? [String: Any] { host.apply(configuration) }
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getMetrics" {
        result(self?.host.runtimeMetrics())
        return
      }
      if call.method == "dispose" {
        self?.host.detachController()
        result(nil)
        return
      }
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

/// One explicit menu/VoiceOver action may dispatch at most once. This is not a
/// fabricated server-completion lock: the existing app callback returns void.
@MainActor
final class NativeTabReadRequest {
  private var used = false
  private let action: () -> Void

  init(action: @escaping () -> Void) { self.action = action }

  func perform() {
    guard !used else { return }
    used = true
    action()
  }
}

/// A contained system controller is required for UIKit's floating tab-bar
/// presentation. These empty child controllers do not own app navigation:
/// Flutter's existing tab stacks remain mounted and receive selection IDs.
@MainActor
final class NativeTabBarHost: UIView, UITabBarControllerDelegate, UIContextMenuInteractionDelegate {
  let controller = UITabBarController()
  var tabBar: UITabBar { controller.tabBar }
  var onSelect: ((Int) -> Void)?
  var onMarkAllRead: ((Int, Int) -> Void)?
  private var menuInteraction: UIContextMenuInteraction?
  private var actionEpoch = 0
  // Configuration's action-provider closure owns the session. The host must
  // not keep a disposed configuration (and its frozen appearance) alive.
  private weak var menuPreviewSession: MenuPreviewSession?
  private let menuPreviewSessions = NSMapTable<UIContextMenuConfiguration, MenuPreviewSession>(
    keyOptions: .weakMemory, valueOptions: .weakMemory
  )
  private final class MenuPreviewSession {
    weak var configuration: UIContextMenuConfiguration?
    weak var item: UITabBarItem?
    weak var control: UIControl?
    weak var window: UIWindow?
    let id: Int
    let epoch: Int
    let sourceRect: CGRect
    let sourceRectInWindow: CGRect
    let sourceCenterInWindow: CGPoint
    var valid = true
    var preview: UITargetedPreview?

    init(item: UITabBarItem, control: UIControl, window: UIWindow,
         epoch: Int, sourceRect: CGRect) {
      self.item = item
      self.control = control
      self.window = window
      self.id = item.tag
      self.epoch = epoch
      self.sourceRect = sourceRect
      self.sourceRectInWindow = control.convert(control.bounds, to: window)
      self.sourceCenterInWindow = control.convert(
        CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: window
      )
    }
  }
  // Narrow draw-failure/argument-observation seam. The real-window fixture
  // exercises UIKit drawing, not a synthetic replacement for item artwork.
  var menuHierarchyDrawing: (UITabBar, CGRect, Bool) -> Bool = {
    $0.drawHierarchy(in: $1, afterScreenUpdates: $2)
  }
  private var readActionImage: UIImage?
  private var readableIDs = Set<Int>()
  private var readActionTitle = ""
  var onMetrics: (([String: Any]) -> Void)?
  private var lastMetrics: NSDictionary?
  private var images: [Int: (Data, Data, CGFloat)] = [:]
  private var reservedBottomInset: CGFloat = 0
  private final class ControlReadBinding {
    let id: Int
    let epoch: Int
    let token: UUID
    let action: UIAccessibilityCustomAction

    init(id: Int, epoch: Int, token: UUID, action: UIAccessibilityCustomAction) {
      self.id = id
      self.epoch = epoch
      self.token = token
      self.action = action
    }
  }
  private let itemReadActions = NSMapTable<UITabBarItem, UIAccessibilityCustomAction>(
    keyOptions: .weakMemory, valueOptions: .strongMemory
  )
  private let controlReadBindings = NSMapTable<UIControl, ControlReadBinding>(
    keyOptions: .weakMemory, valueOptions: .strongMemory
  )

  // The compact shell reserves the indicator once; a split sidebar does not
  // inherit the whole window's indicator into its own narrow control column.
  override var safeAreaInsets: UIEdgeInsets {
    var insets = super.safeAreaInsets
    insets.top = 0
    insets.bottom = reservedBottomInset
    return insets
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    controller.delegate = self
    // Keep the embedded tab row compact on iPad. The Flutter root controller
    // separately disables window-wide vertical bars on iPhone Duo; a size-class
    // override alone does not control that independent UIKit adaptation.
    if #available(iOS 17.0, *) {
      controller.traitOverrides.horizontalSizeClass = .compact
    }
    if #available(iOS 18.0, *) {
      controller.mode = .tabBar
    }
    controller.loadViewIfNeeded()
    controller.view.backgroundColor = .clear
    addSubview(controller.view)
    let interaction = UIContextMenuInteraction(delegate: self)
    menuInteraction = interaction
    tabBar.addInteraction(interaction)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { invalidateMenuPreview() }
    updateContainment()
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    updateContainment()
  }

  private func updateContainment() {
    var responder: UIResponder? = superview
    var parent: UIViewController?
    while let current = responder {
      if let viewController = current as? UIViewController {
        parent = viewController
        break
      }
      responder = current.next
    }
    if window == nil { parent = nil }
    guard controller.parent !== parent else { return }
    if controller.parent != nil {
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
    }
    if let parent {
      parent.addChild(controller)
      addSubview(controller.view)
      controller.didMove(toParent: parent)
    }
    setNeedsLayout()
  }

  func detachController() {
    invalidateMenuPreview()
    guard controller.parent != nil else { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  func apply(_ configuration: [String: Any]) {
    invalidateMenuPreview()
    // A new configuration starts a fresh explicit-read cycle, even when its
    // scope epoch is unchanged. Layout alone must not rearm one-shot actions.
    invalidateControlReadBindings()
    let style: UIUserInterfaceStyle = configuration["dark"] as? Bool == true ? .dark : .light
    overrideUserInterfaceStyle = style
    controller.overrideUserInterfaceStyle = style
    let rtl = configuration["rtl"] as? Bool == true
    controller.view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
    tabBar.semanticContentAttribute = controller.view.semanticContentAttribute
    if let argb = configuration["tint"] as? NSNumber {
      let value = argb.uint32Value
      tabBar.tintColor = UIColor(
        red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255,
        alpha: CGFloat((value >> 24) & 255) / 255
      )
    }
    let bottom = (configuration["bottomInset"] as? NSNumber)?.doubleValue ?? 0
    reservedBottomInset = bottom.isFinite ? CGFloat(max(0, bottom)) : 0
    let nextEpoch = (configuration["actionEpoch"] as? NSNumber)?.intValue ?? 0
    if nextEpoch != actionEpoch { menuInteraction?.dismissMenu() }
    actionEpoch = nextEpoch
    if let image = configuration["readActionImage"] as? FlutterStandardTypedData {
      let scale = max(1, (configuration["imageScale"] as? NSNumber)?.doubleValue ?? 1)
      readActionImage = UIImage(data: image.data, scale: CGFloat(scale))?
        .withRenderingMode(.alwaysTemplate)
    }
    readActionTitle = configuration["markAllReadLabel"] as? String ?? ""
    readableIDs.removeAll()
    let definitions = configuration["items"] as? [[String: Any]] ?? []
    let oldControllers = controller.viewControllers ?? []
    let byID = Dictionary(
      oldControllers.map { ($0.tabBarItem.tag, $0) }, uniquingKeysWith: { first, _ in first }
    )
    var seen = Set<Int>()
    var children: [UIViewController] = []
    for definition in definitions {
      guard let id = (definition["id"] as? NSNumber)?.intValue,
        seen.insert(id).inserted else { continue }
      let child = byID[id] ?? UIViewController()
      child.loadViewIfNeeded()
      child.view.backgroundColor = .clear
      child.view.isUserInteractionEnabled = false
      let item = child.tabBarItem!
      item.tag = id
      item.title = definition["label"] as? String ?? ""
      item.accessibilityLabel = item.title
      item.accessibilityIdentifier = "bottom-tab-\(id)"
      let count = max(0, (definition["unread"] as? NSNumber)?.int64Value ?? 0)
      item.badgeValue = count > 0 ? String(count) : nil
      item.accessibilityValue = item.badgeValue
      let previousAction = itemReadActions.object(forKey: item)
      var itemActions = (item.accessibilityCustomActions ?? []).filter { $0 !== previousAction }
      if definition["canMarkAllRead"] as? Bool == true && !readActionTitle.isEmpty {
        readableIDs.insert(id)
        let action = readAccessibilityAction(for: id)
        itemReadActions.setObject(action, forKey: item)
        itemActions.append(action)
      } else {
        itemReadActions.removeObject(forKey: item)
      }
      item.accessibilityCustomActions = itemActions.isEmpty ? nil : itemActions
      let scaleValue = (definition["imageScale"] as? NSNumber)?.doubleValue ?? 1
      let scale = scaleValue.isFinite && scaleValue > 0 ? CGFloat(scaleValue) : 1
      if let normal = definition["image"] as? FlutterStandardTypedData,
        let selected = definition["selectedImage"] as? FlutterStandardTypedData {
        let previous = images[id]
        if previous?.0 != normal.data || previous?.1 != selected.data || previous?.2 != scale {
          item.image = UIImage(data: normal.data, scale: scale)?.withRenderingMode(.alwaysTemplate)
          item.selectedImage = UIImage(data: selected.data, scale: scale)?
            .withRenderingMode(.alwaysTemplate)
          images[id] = (normal.data, selected.data, scale)
        }
      }
      children.append(child)
    }
    images = images.filter { seen.contains($0.key) }
    if oldControllers.map({ $0.tabBarItem.tag }) != children.map({ $0.tabBarItem.tag }) {
      controller.setViewControllers(children, animated: false)
    }
    let selectedID = (configuration["selectedId"] as? NSNumber)?.intValue
    if let selected = children.first(where: { $0.tabBarItem.tag == selectedID }),
      controller.selectedViewController !== selected {
      controller.selectedViewController = selected
    }
    // Repeat handshake: first layout may precede Dart's channel handler.
    lastMetrics = nil
    controller.view.setNeedsLayout()
    setNeedsLayout()
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    guard tabBarController.viewControllers?.contains(where: { $0 === viewController }) == true
      else { return }
    // UIKit forwards reselect too. App routing/pop-to-root remains in Flutter.
    onSelect?(viewController.tabBarItem.tag)
  }

  func performMarkAllRead(id: Int, epoch: Int) {
    guard epoch == actionEpoch, readableIDs.contains(id),
      controller.viewControllers?.contains(where: { $0.tabBarItem.tag == id }) == true
      else { return }
    onMarkAllRead?(id, epoch)
  }

  func readRequest(for id: Int) -> NativeTabReadRequest {
    let epoch = actionEpoch
    return NativeTabReadRequest { [weak self] in
      self?.performMarkAllRead(id: id, epoch: epoch)
    }
  }

  private func readAccessibilityAction(for id: Int) -> UIAccessibilityCustomAction {
    let epoch = actionEpoch
    let request = readRequest(for: id)
    weak var installedAction: UIAccessibilityCustomAction?
    let action = UIAccessibilityCustomAction(name: readActionTitle) { [weak self] _ in
      guard let self, let installedAction, self.actionEpoch == epoch,
        self.readableIDs.contains(id), self.uniqueLiveControl(for: id) != nil,
        self.tabBar.items?.first(where: { $0.tag == id })?.accessibilityCustomActions?
          .contains(where: { $0 === installedAction }) == true else { return false }
      request.perform()
      return true
    }
    installedAction = action
    return action
  }

  /// Use only public identity and, when UIKit omits it, unique exact public
  /// UILabel title content. Never use private types/keys, order or tab slots.
  /// A present but unknown/ambiguous accessibility identity fails closed.
  func itemID(for control: UIControl) -> Int? {
    let items = tabBar.items ?? []
    if let identifier = control.accessibilityIdentifier {
      let identified = items.filter { $0.accessibilityIdentifier == identifier }
      return identified.count == 1 ? identified[0].tag : nil
    }
    if let label = control.accessibilityLabel {
      guard !label.isEmpty else { return nil }
      let labeled = items.filter { $0.accessibilityLabel == label }
      return labeled.count == 1 ? labeled[0].tag : nil
    }
    var titles = Set<String>()
    func collectTitles(in view: UIView) {
      if let label = view as? UILabel {
        if let text = label.text, !text.isEmpty { titles.insert(text) }
        if let text = label.attributedText?.string, !text.isEmpty { titles.insert(text) }
      }
      for child in view.subviews { collectTitles(in: child) }
    }
    collectTitles(in: control)
    let titled = items.filter {
      guard let title = $0.title, !title.isEmpty else { return false }
      return titles.contains(title)
    }
    return titled.count == 1 ? titled[0].tag : nil
  }

  /// Floating UIKit may keep visual copies of a tab control. A real input
  /// control must occur in the actual hit-test ancestry at its own center.
  /// These are observed control bounds, not computed per-item hit regions.
  func isLiveControl(_ control: UIControl) -> Bool {
    guard control.isDescendant(of: tabBar), control.window != nil,
      control.bounds.width > 0, control.bounds.height > 0 else { return false }
    let center = control.convert(
      CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: tabBar
    )
    guard tabBar.bounds.inset(by: tabBar.safeAreaInsets).contains(center) else { return false }
    var view = tabBar.hitTest(center, with: nil)
    while let current = view, current !== tabBar {
      if current === control { return true }
      view = current.superview
    }
    return false
  }

  func contextMenuItem(at location: CGPoint) -> UITabBarItem? {
    // The indicator and inter-item gaps are not tab-body targets.
    guard tabBar.bounds.contains(location) else { return nil }
    var view = tabBar.hitTest(location, with: nil)
    while let current = view, current !== tabBar {
      if let control = current as? UIControl {
        guard let id = itemID(for: control), uniqueLiveControl(for: id) === control else {
          return nil
        }
        return tabBar.items?.first { $0.tag == id }
      }
      view = current.superview
    }
    return nil
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let item = contextMenuItem(at: location), readableIDs.contains(item.tag),
      let control = uniqueLiveControl(for: item.tag), let window else { return nil }
    menuPreviewSession?.valid = false
    let session = MenuPreviewSession(
      item: item, control: control, window: window, epoch: actionEpoch,
      sourceRect: control.convert(control.bounds, to: tabBar)
    )
    let id = item.tag
    let title = item.title ?? ""
    let actionTitle = readActionTitle
    let epoch = actionEpoch
    let request = NativeTabReadRequest { [weak self] in
      guard let self, self.uniqueLiveControl(for: id) != nil else { return }
      self.performMarkAllRead(id: id, epoch: epoch)
    }
    let configuration = UIContextMenuConfiguration(
      identifier: NSNumber(value: id), previewProvider: nil
    ) { [weak self, session] _ in
      // Retain the session exactly as long as this configuration, even before
      // the first preview callback. Never resolve a later session by numeric ID.
      withExtendedLifetime(session) {}
      return UIMenu(title: title, children: [
        UIAction(title: actionTitle, image: self?.readActionImage) { _ in
          request.perform()
        }
      ])
    }
    session.configuration = configuration
    menuPreviewSession = session
    menuPreviewSessions.setObject(session, forKey: configuration)
    return configuration
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
  ) -> UITargetedPreview? {
    menuPreview(for: configuration)
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
  ) -> UITargetedPreview? {
    menuPreview(for: configuration)
  }

  private func menuPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let session = menuPreviewSession, session.configuration === configuration,
      session.valid else { return nil }
    guard menuSourceIsCurrent(session), let window else {
      invalidateMenuPreview()
      return nil
    }
    if let preview = session.preview { return preview }
    // Snapshot only the actual native control's current rect, in TAB BAR
    // bounds coordinates. A native badge can be composited outside the control
    // subtree; snapshotting the control itself would leave that badge behind.
    let rect = session.sourceRect
    guard let image = menuSnapshotImage(in: rect), session.valid,
      menuPreviewSession === session, menuSourceIsCurrent(session) else {
      invalidateMenuPreview() // Never fall back to lifting the live control.
      return nil
    }
    let snapshot = UIImageView(image: image)
    snapshot.frame = CGRect(origin: .zero, size: rect.size)
    let parameters = UIPreviewParameters()
    parameters.backgroundColor = .clear
    let preview = UITargetedPreview(
      view: snapshot, parameters: parameters,
      target: UIPreviewTarget(container: window, center: session.sourceCenterInWindow)
    )
    // Designated initializer supports this detached snapshot. Do not insert it
    // into the source hierarchy or mutate/hide any live native item or badge.
    session.preview = preview
    return preview
  }

  private func menuSnapshotImage(in rect: CGRect) -> UIImage? {
    guard rect.origin.x.isFinite, rect.origin.y.isFinite,
      rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
      let window = tabBar.window else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = window.screen.scale
    format.opaque = false
    var drawn = false
    let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
      // Rasterize the already-composited native bar into ONLY the mapped item's
      // crop. No icon/text/badge is reconstructed, and no source view is hidden.
      context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
      // Capture the settled, already-live appearance without forcing a screen
      // update/commit from inside the context-menu delegate.
      drawn = menuHierarchyDrawing(tabBar, tabBar.bounds, false)
    }
    guard drawn, let pixels = image.cgImage, pixels.width > 0, pixels.height > 0,
      image.size.width.isFinite, image.size.height.isFinite,
      image.size.width > 0, image.size.height > 0 else { return nil }
    // Own actual pixels when UIKit snapshots the detached UIImageView; do not
    // rely on a detached snapshot container preserving render-server contents.
    return image
  }

  private func menuSourceIsCurrent(_ session: MenuPreviewSession) -> Bool {
    guard let item = session.item, item.tag == session.id, session.epoch == actionEpoch,
      readableIDs.contains(session.id),
      tabBar.items?.contains(where: { $0 === item }) == true,
      let control = session.control, uniqueLiveControl(for: session.id) === control,
      let window, session.window === window else { return false }
    // A host/ancestor can move within the same window without changing the
    // bar-local crop. The frozen preview's fixed window target must still match.
    return control.convert(control.bounds, to: tabBar) == session.sourceRect &&
      control.convert(control.bounds, to: window) == session.sourceRectInWindow &&
      control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: window) ==
        session.sourceCenterInWindow
  }

  private func invalidateMenuPreview() {
    guard let session = menuPreviewSession, session.valid else { return }
    session.valid = false
    menuInteraction?.dismissMenu()
    // Keep the frozen view through UIKit's end animation. If UIKit never
    // presented this configuration, configuration disposal releases it instead.
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    guard let session = menuPreviewSessions.object(forKey: configuration),
      session.configuration === configuration else { return }
    let cleanup = { [weak self, session] in
      session.valid = false
      session.preview = nil
      if self?.menuPreviewSession === session { self?.menuPreviewSession = nil }
    }
    if let animator {
      animator.addCompletion(cleanup)
    } else {
      cleanup()
    }
  }

  private func uniqueLiveControl(for id: Int) -> UIControl? {
    let controls = matchingControls(in: tabBar, id: id)
    return controls.count == 1 ? controls[0] : nil
  }

  private func matchingControls(in view: UIView, id: Int) -> [UIControl] {
    var controls: [UIControl] = []
    if let control = view as? UIControl, itemID(for: control) == id, isLiveControl(control) {
      controls.append(control)
    }
    for child in view.subviews { controls.append(contentsOf: matchingControls(in: child, id: id)) }
    return controls
  }

  private func mappedControlIDs() -> [Int] {
    (tabBar.items ?? []).compactMap { item in
      guard let control = uniqueLiveControl(for: item.tag) else { return nil }
      let center = control.convert(
        CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: tabBar
      )
      return contextMenuItem(at: center)?.tag == item.tag ? item.tag : nil
    }
  }

  func runtimeMetrics() -> [String: Any] {
    setNeedsLayout()
    layoutIfNeeded()
    return lastMetrics as? [String: Any] ?? [:]
  }

  private func invalidateControlReadBindings() {
    let controls = controlReadBindings.keyEnumerator().allObjects.compactMap { $0 as? UIControl }
    for control in controls {
      guard let binding = controlReadBindings.object(forKey: control) else { continue }
      let actions = (control.accessibilityCustomActions ?? []).filter { $0 !== binding.action }
      control.accessibilityCustomActions = actions.isEmpty ? nil : actions
    }
    controlReadBindings.removeAllObjects()
  }

  private func removeDetachedControlActions() {
    let controls = controlReadBindings.keyEnumerator().allObjects.compactMap { $0 as? UIControl }
    for control in controls where !control.isDescendant(of: tabBar) {
      guard let binding = controlReadBindings.object(forKey: control) else { continue }
      let actions = (control.accessibilityCustomActions ?? []).filter { $0 !== binding.action }
      control.accessibilityCustomActions = actions.isEmpty ? nil : actions
      controlReadBindings.removeObject(forKey: control)
    }
  }

  private func updateControlAccessibility(in view: UIView) {
    if let control = view as? UIControl {
      let previous = controlReadBindings.object(forKey: control)
      // Preserve actions installed by UIKit/other owners, removing only ours.
      var actions = (control.accessibilityCustomActions ?? []).filter {
        $0 !== previous?.action
      }
      if let id = itemID(for: control), readableIDs.contains(id),
        uniqueLiveControl(for: id) === control {
        let binding: ControlReadBinding
        if let previous, previous.id == id, previous.epoch == actionEpoch,
          previous.action.name == readActionTitle {
          binding = previous
        } else {
          let token = UUID()
          let epoch = actionEpoch
          let request = readRequest(for: id)
          let action = UIAccessibilityCustomAction(name: readActionTitle) {
            [weak self, weak control] _ in
            guard let self, let control, self.actionEpoch == epoch,
              let current = self.controlReadBindings.object(forKey: control),
              current.token == token, current.id == id, self.readableIDs.contains(id),
              self.itemID(for: control) == id,
              self.uniqueLiveControl(for: id) === control,
              control.accessibilityCustomActions?.contains(where: { $0 === current.action }) == true
              else { return false }
            request.perform()
            return true
          }
          binding = ControlReadBinding(id: id, epoch: epoch, token: token, action: action)
        }
        controlReadBindings.setObject(binding, forKey: control)
        actions.append(binding.action)
      } else {
        controlReadBindings.removeObject(forKey: control)
      }
      control.accessibilityCustomActions = actions.isEmpty ? nil : actions
    }
    for child in view.subviews { updateControlAccessibility(in: child) }
  }

  func naturalHeight(for width: CGFloat) -> CGFloat {
    let fitting = tabBar.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    let intrinsic = tabBar.intrinsicContentSize.height
    let height = fitting.isFinite && fitting > 0 ? fitting : intrinsic
    guard height.isFinite, height > 0 else { return 0 }
    let scale = max(1, traitCollection.displayScale)
    return ceil(height * scale) / scale
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    _ = traitCollection.preferredContentSizeCategory
    _ = traitCollection.accessibilityContrast
    _ = traitCollection.horizontalSizeClass
    _ = traitCollection.verticalSizeClass
    var height = naturalHeight(for: bounds.width)
    guard height > 0 else { return }
    controller.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    controller.view.layoutIfNeeded()
    // Re-query once after real controller layout has resolved safe-area/traits.
    height = naturalHeight(for: bounds.width)
    controller.view.frame.size.height = height
    controller.view.layoutIfNeeded()
    if let session = menuPreviewSession, session.valid, !menuSourceIsCurrent(session) {
      invalidateMenuPreview()
    }
    removeDetachedControlActions()
    updateControlAccessibility(in: tabBar)
    let metrics: [String: Any] = [
      "height": Double(height),
      "barHeight": Double(tabBar.bounds.height),
      "bottomInset": Double(tabBar.safeAreaInsets.bottom),
      "controllerClass": String(describing: type(of: controller)),
      "controlClass": String(describing: type(of: tabBar)),
      "imageWidths": (tabBar.items ?? []).map { Double($0.image?.size.width ?? 0) },
      "imageHeights": (tabBar.items ?? []).map { Double($0.image?.size.height ?? 0) },
      "mappedContextMenuIds": mappedControlIDs().sorted(),
      "selectedId": controller.selectedViewController?.tabBarItem.tag ?? -1,
    ]
    let dictionary = metrics as NSDictionary
    if lastMetrics != dictionary {
      lastMetrics = dictionary
      onMetrics?(metrics)
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }
}
