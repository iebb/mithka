// AppPurchases.swift — reports verified StoreKit purchases to an independent
// application platform. Optional webhook integration can notify the owner.
// The platform verifies the App Store signature on each transaction;
// this file never states a price.
//
// Copy this file into the app target unchanged except for
// `PurchaseConfig.endpoint` and `PurchaseConfig.appKey`. Requires no packages, no Info.plist entries, and
// no account: the public App Key authorizes ingestion only. No separate buyer identifier is
// appended. Apple's original JWS itself includes transaction metadata and may
// contain an app account token supplied by the app to StoreKit.
//
// Usage — two lines:
//   PurchaseReporter.start()                 // at launch: Transaction.updates
//   PurchaseReporter.report(verification)    // after product.purchase() succeeds
//
// Reporting the same transaction twice is expected; the backend keeps one row.

import Foundation
import os
import StoreKit
import UIKit

enum PurchaseConfig {
    /// The `purchaseEndpoint` and public `key` returned by `workers app-key`.
    static let endpoint = URL(string: "https://apps.air.build/v1/ingest/purchases")!
    static let appKey = "ak_production_Knmbmr-NVDAz2VycHPJpjcU06Cr73h9T-6qdA9PrW70"
}

enum PurchaseReporter {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppPurchases")
    @MainActor private static var listener: Task<Void, Never>?

    /// Listens for transactions that arrive outside the purchase flow
    /// (completed while the app was away, renewals, Ask to Buy). Call once
    /// at launch; a second call is ignored. Does not finish transactions —
    /// that stays with the app.
    @MainActor
    static func start() {
        guard listener == nil else { return }
        listener = Task.detached {
            for await result in Transaction.updates {
                report(result)
            }
        }
    }

    /// Call right after a successful `product.purchase()`, before finishing.
    /// Only StoreKit-verified results are sent; anything else would be
    /// refused by the backend anyway.
    static func report(_ result: VerificationResult<Transaction>) {
        guard case .verified(let transaction) = result else { return }
        Task { await send(result.jwsRepresentation, id: String(transaction.id)) }
    }

    /// One POST, one log line, no retry: a report that fails is a sale
    /// missing from the owner's feed, nothing else.
    @MainActor
    private static func send(_ jws: String, id: String) async {
        let info = Bundle.main.infoDictionary ?? [:]
        let body: [String: Any] = [
            "signedTransaction": jws,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": info["CFBundleVersion"] as? String ?? "",
            "osVersion": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "deviceModel": UIDevice.current.model,
        ]
        var request = URLRequest(url: PurchaseConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(PurchaseConfig.appKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let answer = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let detail = answer?["status"] as? String ?? answer?["code"] as? String ?? ""
            log.notice("AppPurchases: reported \(id, privacy: .public) → \(status, privacy: .public) \(detail, privacy: .public)")
        } catch {
            log.notice("AppPurchases: reported \(id, privacy: .public) → error \(String(describing: error), privacy: .public)")
        }
    }
}
