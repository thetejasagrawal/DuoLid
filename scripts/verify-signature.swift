#!/usr/bin/env swift
import CryptoKit
import Foundation

// Public-key-only verification. The optional byte count is used for Sparkle's
// signed XML payload, which precedes its trailing signature comment.
let arguments = CommandLine.arguments
guard arguments.count == 4 || arguments.count == 5,
    let publicBytes = Data(base64Encoded: arguments[1]), publicBytes.count == 32,
    let signature = Data(base64Encoded: arguments[3]), signature.count == 64
else {
    fputs("Usage: verify-signature.swift PUBLIC_KEY FILE SIGNATURE [SIGNED_BYTE_COUNT]\n", stderr)
    exit(64)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    let count = arguments.count == 5 ? Int(arguments[4]) : data.count
    guard let count, count > 0, count <= data.count,
        key.isValidSignature(signature, for: data.prefix(count))
    else {
        fputs("Update signature verification failed.\n", stderr)
        exit(1)
    }
} catch {
    fputs("Unable to verify update signature: \(error.localizedDescription)\n", stderr)
    exit(1)
}
