import Flutter
import StoreKit
import UIKit

// Disabled for every build until the privacy source, retention, and deletion
// policy for purchase reporting are resolved. No runtime or build-mode opt-in.
private enum MithkaPurchaseReportingPolicy {
  static let isEnabled = false
}

@MainActor
final class MithkaProBridge {
  static let monthlyProductID = "ad.neko.mithka.pro.monthly"
  static let yearlyProductID = "ad.neko.mithka.pro.yearly"

  private static let productIDs = [monthlyProductID, yearlyProductID]
  private static let productIDSet = Set(productIDs)

  // Shared with native paid-feature entry points. Always ask StoreKit rather
  // than trusting cached Dart state or the currently selected app icon.
  static func hasActiveSupporterEntitlement() async -> Bool {
    await currentEntitlement() != nil
  }

  private let channel: FlutterMethodChannel
  private var transactionUpdates: Task<Void, Never>?
  private var foregroundUpdates: Task<Void, Never>?
  private var expirationInvalidation: Task<Void, Never>?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mithka/pro", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    if MithkaPurchaseReportingPolicy.isEnabled {
      PurchaseReporter.start()
    }
    transactionUpdates = listenForTransactionUpdates()
    foregroundUpdates = listenForForegroundUpdates()
  }

  deinit {
    transactionUpdates?.cancel()
    foregroundUpdates?.cancel()
    expirationInvalidation?.cancel()
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getState":
      Task { @MainActor in
        result(await self.state())
      }
    case "getProducts":
      Task { @MainActor in
        await self.getProducts(result: result)
      }
    case "purchase":
      guard
        let arguments = call.arguments as? [String: Any],
        let productID = arguments["productId"] as? String,
        Self.productIDSet.contains(productID)
      else {
        result(Self.flutterError(.invalidProduct))
        return
      }
      Task { @MainActor in
        await self.purchase(productID: productID, result: result)
      }
    case "restore":
      Task { @MainActor in
        await self.restore(result: result)
      }
    case "manage":
      Task { @MainActor in
        await self.manage(result: result)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getProducts(result: @escaping FlutterResult) async {
    do {
      let products = try await Product.products(for: Self.productIDs)
      let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
      result(Self.productIDs.compactMap { productID in
        productsByID[productID].map(Self.productMap)
      })
    } catch {
      result(Self.flutterError(.productsUnavailable, underlying: error))
    }
  }

  private func purchase(productID: String, result: @escaping FlutterResult) async {
    do {
      guard AppStore.canMakePayments else {
        throw ProPurchaseError.paymentsNotAllowed
      }
      guard let product = try await Product.products(for: [productID]).first else {
        throw ProPurchaseError.productUnavailable
      }

      switch try await product.purchase() {
      case .success(let verification):
        let transaction = try Self.verified(verification)
        guard Self.productIDSet.contains(transaction.productID) else {
          throw ProPurchaseError.invalidProduct
        }
        if MithkaPurchaseReportingPolicy.isEnabled {
          PurchaseReporter.report(verification)
        }
        await transaction.finish()
        result(await state())
      case .pending:
        throw ProPurchaseError.pending
      case .userCancelled:
        throw ProPurchaseError.cancelled
      @unknown default:
        throw ProPurchaseError.failed
      }
    } catch let error as ProPurchaseError {
      result(Self.flutterError(error))
    } catch {
      result(Self.flutterError(.failed, underlying: error))
    }
  }

  private func restore(result: @escaping FlutterResult) async {
    do {
      try await AppStore.sync()
      result(await state())
    } catch {
      result(Self.flutterError(.restoreFailed, underlying: error))
    }
  }

  private func manage(result: @escaping FlutterResult) async {
    guard let windowScene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive })
    else {
      result(Self.flutterError(.manageUnavailable))
      return
    }
    do {
      try await AppStore.showManageSubscriptions(in: windowScene)
      result(await state())
    } catch {
      result(Self.flutterError(.manageFailed, underlying: error))
    }
  }

  private func state() async -> [String: Any] {
    let distribution = Self.distribution
    let entitlement = await Self.currentEntitlement()
    scheduleExpirationInvalidation(at: entitlement?.expirationDate)
    var response: [String: Any] = [
      // StoreKit is supported here. It has no synchronous connectivity probe;
      // sync/products/manage report their own availability errors. Screen Time
      // restrictions apply only to new purchases, never existing customers.
      "storeAvailable": true,
      "canMakePayments": AppStore.canMakePayments,
      "canManageSubscriptions": UIApplication.shared.connectedScenes.contains {
        $0 is UIWindowScene && $0.activationState == .foregroundActive
      },
      "isPro": entitlement != nil,
      "distribution": distribution.rawValue,
    ]
    if let expirationDate = entitlement?.expirationDate {
      response["expirationDateMillis"] = NSNumber(
        value: Int64(expirationDate.timeIntervalSince1970 * 1_000)
      )
    }
    return response
  }

  private static func currentEntitlement() async -> Transaction? {
    var newestEntitlement: Transaction?
    for await verification in Transaction.currentEntitlements {
      guard
        case .verified(let transaction) = verification,
        Self.productIDSet.contains(transaction.productID),
        transaction.revocationDate == nil,
        transaction.expirationDate.map({ $0 > Date() }) ?? true
      else {
        continue
      }
      if Self.isLater(transaction, than: newestEntitlement) {
        newestEntitlement = transaction
      }
    }
    return newestEntitlement
  }

  private func listenForTransactionUpdates() -> Task<Void, Never> {
    Task { @MainActor [weak self] in
      for await verification in Transaction.updates {
        guard !Task.isCancelled else { return }
        guard
          case .verified(let transaction) = verification,
          Self.productIDSet.contains(transaction.productID)
        else {
          continue
        }
        // PurchaseReporter has its own updates listener. Keep finishing and
        // entitlement invalidation here, without adding a second report hook.
        await transaction.finish()
        await self?.entitlementDidChange()
      }
    }
  }

  private func listenForForegroundUpdates() -> Task<Void, Never> {
    Task { @MainActor [weak self] in
      await self?.refreshExpirationTimer()
      for await _ in NotificationCenter.default.notifications(
        named: UIApplication.didBecomeActiveNotification
      ) {
        guard !Task.isCancelled else { return }
        // Expiration can pass while suspended, without a StoreKit update.
        await self?.entitlementDidChange()
      }
    }
  }

  private func entitlementDidChange() async {
    await refreshExpirationTimer()
    // This is only an invalidation signal. Dart must fetch fresh StoreKit
    // state; neither this callback nor the reporter grants entitlements.
    channel.invokeMethod("entitlementChanged", arguments: nil)
  }

  private func refreshExpirationTimer() async {
    let entitlement = await Self.currentEntitlement()
    scheduleExpirationInvalidation(at: entitlement?.expirationDate)
  }

  private func scheduleExpirationInvalidation(at expirationDate: Date?) {
    expirationInvalidation?.cancel()
    expirationInvalidation = nil
    guard let expirationDate else { return }
    // Bound the conversion well below UInt64.max; StoreKit subscription
    // periods are much shorter. An early wake simply rechecks StoreKit.
    let delay = min(max(0, expirationDate.timeIntervalSinceNow), 10 * 366 * 24 * 60 * 60)
    expirationInvalidation = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      } catch {
        return
      }
      guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
      // Never reset an already selected icon when a subscription expires.
      await self?.entitlementDidChange()
    }
  }

  private static func isLater(_ candidate: Transaction, than current: Transaction?) -> Bool {
    guard let current else { return true }
    switch (candidate.expirationDate, current.expirationDate) {
    case let (candidateExpiration?, currentExpiration?):
      return candidateExpiration > currentExpiration
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return candidate.purchaseDate > current.purchaseDate
    }
  }

  private static func verified<T>(_ verification: VerificationResult<T>) throws -> T {
    switch verification {
    case .verified(let value):
      return value
    case .unverified:
      throw ProPurchaseError.unverified
    }
  }

  private static func productMap(_ product: Product) -> [String: Any] {
    [
      "id": product.id,
      "title": product.displayName,
      "description": product.description,
      "displayPrice": product.displayPrice,
      "period": product.id == monthlyProductID ? "monthly" : "yearly",
    ]
  }

  private static func flutterError(
    _ error: ProPurchaseError,
    underlying: Error? = nil
  ) -> FlutterError {
    FlutterError(
      code: error.code,
      message: underlying?.localizedDescription ?? error.errorDescription,
      details: nil
    )
  }

  private static var distribution: Distribution {
    #if targetEnvironment(simulator)
      return .development
    #else
      guard let receiptURL = Bundle.main.appStoreReceiptURL else {
        return .development
      }
      if receiptURL.lastPathComponent == "sandboxReceipt" {
        let hasEmbeddedProvisioningProfile = Bundle.main.path(
          forResource: "embedded",
          ofType: "mobileprovision"
        ) != nil
        return hasEmbeddedProvisioningProfile ? .development : .testFlight
      }
      return FileManager.default.fileExists(atPath: receiptURL.path)
        ? .appStore
        : .development
    #endif
  }

  private enum Distribution: String {
    case appStore = "app_store"
    case testFlight = "testflight"
    case development
  }

  private enum ProPurchaseError: LocalizedError {
    case invalidProduct
    case paymentsNotAllowed
    case productUnavailable
    case productsUnavailable
    case cancelled
    case pending
    case unverified
    case restoreFailed
    case manageUnavailable
    case manageFailed
    case failed

    var code: String {
      switch self {
      case .invalidProduct: return "pro_invalid_product"
      case .paymentsNotAllowed: return "pro_payments_not_allowed"
      case .productUnavailable: return "pro_product_unavailable"
      case .productsUnavailable: return "pro_products_unavailable"
      case .cancelled: return "pro_purchase_cancelled"
      case .pending: return "pro_purchase_pending"
      case .unverified: return "pro_purchase_unverified"
      case .restoreFailed: return "pro_restore_failed"
      case .manageUnavailable: return "pro_manage_unavailable"
      case .manageFailed: return "pro_manage_failed"
      case .failed: return "pro_purchase_failed"
      }
    }

    var errorDescription: String? {
      switch self {
      case .invalidProduct: return "The Mithka Pro product identifier is invalid"
      case .paymentsNotAllowed: return "New purchases are not allowed on this device"
      case .productUnavailable: return "The Mithka Pro product is unavailable"
      case .productsUnavailable: return "Mithka Pro products could not be loaded"
      case .cancelled: return "The Mithka Pro purchase was cancelled"
      case .pending: return "The Mithka Pro purchase is pending approval"
      case .unverified: return "StoreKit could not verify the Mithka Pro purchase"
      case .restoreFailed: return "Mithka Pro purchases could not be restored"
      case .manageUnavailable: return "Subscription management is unavailable"
      case .manageFailed: return "Subscription management could not be opened"
      case .failed: return "The Mithka Pro purchase failed"
      }
    }
  }
}
