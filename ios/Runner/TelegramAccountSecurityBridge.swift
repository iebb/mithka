import AuthenticationServices
import Flutter
import StoreKit
import UIKit

@MainActor
final class TelegramPasskeyBridge: NSObject,
  ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mithka/passkeys", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      if #available(iOS 16.0, *) {
        result(true)
      } else {
        result(false)
      }
    case "get", "create":
      guard #available(iOS 16.0, *) else {
        result(FlutterError(
          code: "passkey_unavailable",
          message: "Passkeys require iOS 16 or newer",
          details: nil
        ))
        return
      }
      guard pendingResult == nil else {
        result(FlutterError(
          code: "passkey_failed",
          message: "Another passkey request is already active",
          details: nil
        ))
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let publicKeyJSON = arguments["publicKeyJson"] as? String,
        let publicKey = Self.jsonObject(publicKeyJSON)
      else {
        result(FlutterError(
          code: "passkey_invalid",
          message: "Missing public-key request",
          details: nil
        ))
        return
      }
      do {
        let request = try call.method == "get"
          ? assertionRequest(publicKey)
          : registrationRequest(publicKey)
        pendingResult = result
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
      } catch {
        result(FlutterError(
          code: "passkey_invalid",
          message: error.localizedDescription,
          details: nil
        ))
      }
    case "openSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(nil)
        return
      }
      UIApplication.shared.open(url) { opened in
        result(opened ? nil : FlutterError(
          code: "passkey_unavailable",
          message: "Unable to open settings",
          details: nil
        ))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.0, *)
  private func assertionRequest(
    _ publicKey: [String: Any]
  ) throws -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {
    guard
      let relyingPartyID = publicKey["rpId"] as? String,
      relyingPartyID == "telegram.org",
      let challengeValue = publicKey["challenge"] as? String,
      let challenge = Self.base64URLData(challengeValue)
    else {
      throw BridgeError.invalidRequest
    }
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: relyingPartyID
    )
    let request = provider.createCredentialAssertionRequest(challenge: challenge)
    request.userVerificationPreference = Self.userVerification(
      publicKey["userVerification"] as? String
    )
    if let allowed = publicKey["allowCredentials"] as? [[String: Any]] {
      request.allowedCredentials = allowed.compactMap { descriptor in
        guard
          let value = descriptor["id"] as? String,
          let credentialID = Self.base64URLData(value)
        else { return nil }
        return ASAuthorizationPlatformPublicKeyCredentialDescriptor(
          credentialID: credentialID
        )
      }
    }
    return request
  }

  @available(iOS 16.0, *)
  private func registrationRequest(
    _ publicKey: [String: Any]
  ) throws -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest {
    guard
      let relyingParty = publicKey["rp"] as? [String: Any],
      let relyingPartyID = relyingParty["id"] as? String,
      relyingPartyID == "telegram.org",
      let user = publicKey["user"] as? [String: Any],
      let userIDValue = user["id"] as? String,
      let userID = Self.base64URLData(userIDValue),
      let userName = user["name"] as? String,
      let challengeValue = publicKey["challenge"] as? String,
      let challenge = Self.base64URLData(challengeValue)
    else {
      throw BridgeError.invalidRequest
    }
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: relyingPartyID
    )
    let request = provider.createCredentialRegistrationRequest(
      challenge: challenge,
      name: userName,
      userID: userID
    )
    request.displayName = user["displayName"] as? String
    request.userVerificationPreference = Self.userVerification(
      publicKey["authenticatorSelection"] as? [String: Any]
    )
    request.attestationPreference = .direct
    if #available(iOS 17.4, *),
       let excluded = publicKey["excludeCredentials"] as? [[String: Any]]
    {
      request.excludedCredentials = excluded.compactMap { descriptor in
        guard
          let value = descriptor["id"] as? String,
          let credentialID = Self.base64URLData(value)
        else { return nil }
        return ASAuthorizationPlatformPublicKeyCredentialDescriptor(
          credentialID: credentialID
        )
      }
    }
    return request
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    let result = pendingResult
    pendingResult = nil
    guard let result else { return }
    do {
      if #available(iOS 16.0, *),
         let assertion = authorization.credential
           as? ASAuthorizationPlatformPublicKeyCredentialAssertion
      {
        let clientDataJSON = assertion.rawClientDataJSON
        result([
          "responseJson": try Self.jsonString([
            "id": Self.base64URL(assertion.credentialID),
            "rawId": Self.base64URL(assertion.credentialID),
            "type": "public-key",
            "response": [
              "clientDataJSON": Self.base64URL(clientDataJSON),
              "authenticatorData": Self.base64URL(assertion.rawAuthenticatorData),
              "signature": Self.base64URL(assertion.signature),
              "userHandle": Self.base64URL(assertion.userID),
            ],
          ]),
          "clientDataJson": String(data: clientDataJSON, encoding: .utf8) ?? "",
        ])
        return
      }
      if #available(iOS 16.0, *),
         let registration = authorization.credential
           as? ASAuthorizationPlatformPublicKeyCredentialRegistration
      {
        guard let attestation = registration.rawAttestationObject else {
          throw BridgeError.missingAttestation
        }
        let clientDataJSON = registration.rawClientDataJSON
        result([
          "responseJson": try Self.jsonString([
            "id": Self.base64URL(registration.credentialID),
            "rawId": Self.base64URL(registration.credentialID),
            "type": "public-key",
            "response": [
              "clientDataJSON": Self.base64URL(clientDataJSON),
              "attestationObject": Self.base64URL(attestation),
            ],
          ]),
          "clientDataJson": String(data: clientDataJSON, encoding: .utf8) ?? "",
        ])
        return
      }
      throw BridgeError.invalidResponse
    } catch {
      result(FlutterError(
        code: "passkey_invalid",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    let result = pendingResult
    pendingResult = nil
    guard let result else { return }
    let authorizationError = error as? ASAuthorizationError
    let code = authorizationError?.code == .canceled
      ? "passkey_cancelled"
      : "passkey_failed"
    result(FlutterError(code: code, message: error.localizedDescription, details: nil))
  }

  func presentationAnchor(
    for controller: ASAuthorizationController
  ) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
      ?? ASPresentationAnchor()
  }

  @available(iOS 16.0, *)
  private static func userVerification(
    _ value: String?
  ) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
    switch value {
    case "required": return .required
    case "discouraged": return .discouraged
    default: return .preferred
    }
  }

  @available(iOS 16.0, *)
  private static func userVerification(
    _ selection: [String: Any]?
  ) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
    userVerification(selection?["userVerification"] as? String)
  }

  private static func jsonObject(_ value: String) -> [String: Any]? {
    guard let data = value.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private static func jsonString(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    guard let string = String(data: data, encoding: .utf8) else {
      throw BridgeError.invalidResponse
    }
    return string
  }

  private static func base64URLData(_ value: String) -> Data? {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
      base64.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: base64)
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private enum BridgeError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case missingAttestation

    var errorDescription: String? {
      switch self {
      case .invalidRequest: return "Invalid passkey request"
      case .invalidResponse: return "Invalid passkey response"
      case .missingAttestation: return "Passkey registration returned no attestation"
      }
    }
  }
}

@MainActor
final class PremiumAuthPurchaseBridge {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "mithka/premium_auth_purchase",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "restoreTransactions":
      Task { @MainActor in
        await self.restoreTransactions(result: result)
      }
    case "productInfo", "purchase":
      guard
        let arguments = call.arguments as? [String: Any],
        let productID = arguments["productId"] as? String,
        !productID.isEmpty
      else {
        result(FlutterError(
          code: "purchase_invalid",
          message: "A StoreKit product identifier is required",
          details: nil
        ))
        return
      }
      let restore = arguments["restore"] as? Bool ?? false
      Task { @MainActor in
        await self.process(
          method: call.method,
          productID: productID,
          restore: restore,
          result: result
        )
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func restoreTransactions(result: @escaping FlutterResult) async {
    do {
      try await AppStore.sync()
      result(["receipt": FlutterStandardTypedData(bytes: try Self.receipt())])
    } catch let error as PurchaseError {
      result(FlutterError(
        code: error.code,
        message: error.localizedDescription,
        details: nil
      ))
    } catch {
      result(FlutterError(
        code: "purchase_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func process(
    method: String,
    productID: String,
    restore: Bool,
    result: @escaping FlutterResult
  ) async {
    do {
      guard let product = try await Product.products(for: [productID]).first else {
        throw PurchaseError.productUnavailable
      }
      let productInfo = Self.productInfo(product)
      if method == "productInfo" {
        result(productInfo)
        return
      }

      if restore {
        try await AppStore.sync()
      } else {
        switch try await product.purchase() {
        case .success(let verification):
          let transaction = try Self.verified(verification)
          await transaction.finish()
        case .pending:
          throw PurchaseError.pending
        case .userCancelled:
          throw PurchaseError.cancelled
        @unknown default:
          throw PurchaseError.failed
        }
      }

      if restore {
        try await AppStore.sync()
      }
      let receipt = try Self.receipt()
      var response = productInfo
      response["receipt"] = FlutterStandardTypedData(bytes: receipt)
      result(response)
    } catch let error as PurchaseError {
      result(FlutterError(
        code: error.code,
        message: error.localizedDescription,
        details: nil
      ))
    } catch {
      result(FlutterError(
        code: "purchase_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let value): return value
    case .unverified: throw PurchaseError.unverified
    }
  }

  private static func receipt() throws -> Data {
    guard
      let receiptURL = Bundle.main.appStoreReceiptURL,
      let receipt = try? Data(contentsOf: receiptURL),
      !receipt.isEmpty
    else {
      throw PurchaseError.missingReceipt
    }
    return receipt
  }

  private static func productInfo(_ product: Product) -> [String: Any] {
    let currency = product.priceFormatStyle.currencyCode
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    let fractionDigits = max(0, formatter.maximumFractionDigits)
    let amount = NSDecimalNumber(decimal: product.price)
      .multiplying(byPowerOf10: Int16(fractionDigits))
      .rounding(accordingToBehavior: NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 0,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
      ))
      .int64Value
    return [
      "currency": currency,
      "amount": NSNumber(value: amount),
      "displayPrice": product.displayPrice,
    ]
  }

  private enum PurchaseError: LocalizedError {
    case productUnavailable
    case pending
    case cancelled
    case unverified
    case missingReceipt
    case failed

    var code: String {
      switch self {
      case .cancelled: return "purchase_cancelled"
      case .productUnavailable: return "purchase_product_unavailable"
      case .pending: return "purchase_pending"
      case .unverified: return "purchase_unverified"
      case .missingReceipt: return "purchase_missing_receipt"
      case .failed: return "purchase_failed"
      }
    }

    var errorDescription: String? {
      switch self {
      case .productUnavailable: return "The required App Store product is unavailable"
      case .pending: return "The purchase is pending approval"
      case .cancelled: return "The purchase was cancelled"
      case .unverified: return "StoreKit could not verify the purchase"
      case .missingReceipt: return "The App Store receipt is unavailable"
      case .failed: return "The purchase failed"
      }
    }
  }
}
