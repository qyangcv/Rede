import CryptoKit
import Foundation

let arguments = CommandLine.arguments
let keyID = arguments[1]
let issuerID = arguments[2]
let keyPath = arguments[3]

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let now = Int(Date().timeIntervalSince1970)
let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
let payload: [String: Any] = ["iss": issuerID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"]

let signingInput = try [header, payload]
    .map { base64URL(try JSONSerialization.data(withJSONObject: $0)) }
    .joined(separator: ".")

let key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOfFile: keyPath, encoding: .utf8))
let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation

print(signingInput + "." + base64URL(signature))
