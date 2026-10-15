import CryptoKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let key = Curve25519.Signing.PrivateKey()
let seed = directory.appendingPathComponent("test-private-key")
try key.rawRepresentation.base64EncodedData().write(to: seed)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: seed.path)
let payload = directory.appendingPathComponent("archive.zip")
try Data("original update archive".utf8).write(to: payload)
print(key.publicKey.rawRepresentation.base64EncodedString())
print(try key.signature(for: Data(contentsOf: payload)).base64EncodedString())
