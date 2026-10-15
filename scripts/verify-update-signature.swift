import CryptoKit
import Foundation

// Verify against the public key embedded in the ZIP, independently of the signing process.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
      let archive = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])),
      publicKey.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("update archive signature does not match its embedded public key\n".utf8))
    exit(1)
}
