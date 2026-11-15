// AirDeviceProof.swift — proves to AirFeedback that a report came from your
// genuine app on a real Apple device (App Attest), so the owner can hide the
// rest. AppFeedback.swift and AirCrashReports.swift use it; copy it beside
// them, unchanged.
//
// Never a gate. A report is sent and stored either way: without a proof it
// is marked unverified (shown as 未验证 / Unverified). No proof is made on
// the Simulator, on a Mac app outside the Mac App Store or without the
// capability, on a build whose App Attest key is a development one, when
// Apple cannot be reached, or before `teamID` is set.
//
// Setup:
//   1. Xcode › target › Signing & Capabilities › + Capability › App Attest.
//      That adds `com.apple.developer.devicecheck.appattest-environment`
//      (`development`) to the entitlements. App Store and TestFlight builds
//      always attest in production, whatever the value. Local builds attest
//      in development, and the platform refuses development keys (anyone
//      can sideload such a build), so their reports stay unverified.
//   2. Register the app's bundle id on its App Key:
//      `workers keys` / the console's App Key, `bundleId`.
//   3. Pass the Apple team id (10 characters, the build's DEVELOPMENT_TEAM) as
//      `FeedbackConfig.teamID` and `AirCrashReports.start(…, teamID:)`.
//
// How it works:
//   - Once per install, it asks `…/v1/ingest/attestation/challenge` for a
//     challenge, has Apple attest a new Secure Enclave key over it, and
//     posts the attestation to `…/v1/ingest/attestation`.
//   - Each report then carries `X-Attest-Key-Id` and `X-Attest-Assertion`,
//     an assertion over SHA-256 of the exact body bytes.
//   - The answer's `X-Attest-Status` is `verified`, `unverified` or
//     `unknown-key`. On `unknown-key` the key is dropped and attested again
//     next time. iOS 14 / macOS 11 or later.

import CryptoKit
import DeviceCheck
import Foundation

nonisolated enum AirDeviceProof {
    /// The headers to add to a report whose body is exactly `body`, posted
    /// to `endpoint` (`…/v1/ingest/feedback` or `…/v1/ingest/crashes`) with
    /// `appKey`. Empty when there is no proof; never throws.
    static func headers(for body: Data, endpoint: URL, appKey: String, teamID: String?) async -> [String: String] {
        await Store.shared.headers(for: body, endpoint: endpoint, appKey: appKey, teamID: teamID)
    }

    /// Hand it the answer's `X-Attest-Status`; `unknown-key` drops the key.
    static func handle(status: String?) async {
        if status == "unknown-key" {
            await Store.shared.forget()
        }
    }

    private actor Store {
        static let shared = Store()
        private let keyIDKey = "AirDeviceProof.keyID"
        private let refusedKey = "AirDeviceProof.refusedBuild"

        func forget() {
            UserDefaults.standard.removeObject(forKey: keyIDKey)
        }

        func headers(for body: Data, endpoint: URL, appKey: String, teamID: String?) async -> [String: String] {
            let service = DCAppAttestService.shared
            guard service.isSupported,
                  let teamID, teamID.count == 10,
                  let bundleID = Bundle.main.bundleIdentifier
            else { return [:] }
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            // The platform refused this build's attestation (a development
            // key, a bundle id it does not expect): do not ask again.
            if UserDefaults.standard.string(forKey: refusedKey) == build { return [:] }
            var keyID = UserDefaults.standard.string(forKey: keyIDKey)
            if keyID == nil {
                keyID = await attest(service, appID: "\(teamID).\(bundleID)", endpoint: endpoint, appKey: appKey, build: build)
            }
            guard let keyID else { return [:] }
            do {
                let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: body)))
                return ["X-Attest-Key-Id": keyID, "X-Attest-Assertion": assertion.base64EncodedString()]
            } catch let error as DCError where error.code == .invalidKey {
                forget() // Apple dropped the key: a new one next time.
                return [:]
            } catch {
                return [:]
            }
        }

        private func attest(_ service: DCAppAttestService, appID: String, endpoint: URL, appKey: String, build: String) async -> String? {
            let base = endpoint.deletingLastPathComponent().appendingPathComponent("attestation")
            do {
                let (data, status) = try await post(base.appendingPathComponent("challenge"), body: nil, appKey: appKey)
                guard status == 201,
                      let challenge = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["challenge"] as? String
                else { return nil }
                let keyID = try await service.generateKey()
                let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
                let body = try JSONSerialization.data(withJSONObject: [
                    "scheme": "app-attest", "keyId": keyID, "attestation": attestation.base64EncodedString(),
                    "challenge": challenge, "appId": appID,
                ])
                switch try await post(base, body: body, appKey: appKey).1 {
                case 201:
                    UserDefaults.standard.set(keyID, forKey: keyIDKey)
                    return keyID
                case 422:
                    UserDefaults.standard.set(build, forKey: refusedKey)
                    return nil
                default:
                    return nil
                }
            } catch {
                return nil
            }
        }

        private func post(_ url: URL, body: Data?, appKey: String) async throws -> (Data, Int) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(appKey)", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}
