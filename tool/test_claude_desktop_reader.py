#!/usr/bin/env python3
"""Compile the macOS cookie decoder and verify synthetic fixtures without credentials."""

from pathlib import Path
import platform
import subprocess
import tempfile


HARNESS = r'''
private func encryptFixture(_ plaintext: Data, password: Data) throws -> Data {
    var key = Data(count: kCCKeySizeAES128)
    let salt = Data("saltysalt".utf8)
    let derivation = key.withUnsafeMutableBytes { output in
        password.withUnsafeBytes { secret in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    secret.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    output.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128)
            }
        }
    }
    precondition(derivation == kCCSuccess)
    let vector = Data(repeating: 32, count: kCCBlockSizeAES128)
    var encrypted = Data(count: plaintext.count + kCCBlockSizeAES128)
    var written = 0
    let status = encrypted.withUnsafeMutableBytes { output in
        plaintext.withUnsafeBytes { input in
            key.withUnsafeBytes { keyBytes in
                vector.withUnsafeBytes { vectorBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count,
                        vectorBytes.baseAddress, input.baseAddress, plaintext.count,
                        output.baseAddress, output.count, &written)
                }
            }
        }
    }
    precondition(status == kCCSuccess)
    encrypted.count = written
    return Data("v10".utf8) + encrypted
}

private var checks = 0
private func verify(_ condition: Bool, _ label: String) {
    guard condition else { fatalError("Synthetic check failed: \(label)") }
    checks += 1
}
private func rejects(_ label: String, _ body: () throws -> Void) {
    do {
        try body()
        fatalError("Synthetic check unexpectedly succeeded: \(label)")
    } catch {
        verify(error is ClaudeDesktopSessionReader.ReadError, label)
    }
}

let password = Data("synthetic-safe-storage-password".utf8)
let host = ".claude.ai"
let session = "sk-ant-sid01-synthetic-fixture-value"
let legacy = try encryptFixture(Data(session.utf8), password: password)
verify(try ClaudeDesktopSessionReader.decode(legacy, host: host, version: 23, password: password) == session,
       "legacy v10 cookie")
let bound = Data(SHA256.hash(data: Data(host.utf8))) + Data(session.utf8)
let modern = try encryptFixture(bound, password: password)
verify(try ClaudeDesktopSessionReader.decode(modern, host: host, version: 24, password: password) == session,
       "modern host-bound cookie")
rejects("wrong host digest") {
    _ = try ClaudeDesktopSessionReader.decode(modern, host: "claude.ai", version: 24, password: password)
}
rejects("modern cookie without host digest") {
    _ = try ClaudeDesktopSessionReader.decode(legacy, host: host, version: 24, password: password)
}
rejects("unsupported encryption version") {
    _ = try ClaudeDesktopSessionReader.decode(Data("v11".utf8) + modern.dropFirst(3),
        host: host, version: 24, password: password)
}
rejects("truncated ciphertext") {
    _ = try ClaudeDesktopSessionReader.decode(Data(modern.dropLast()),
        host: host, version: 24, password: password)
}
let invalidText = try encryptFixture(Data([0xff, 0xfe]), password: password)
rejects("invalid UTF-8") {
    _ = try ClaudeDesktopSessionReader.decode(invalidText, host: host, version: 23, password: password)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let databaseURL = directory.appendingPathComponent("fixture.sqlite")
var database: OpaquePointer?
precondition(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
let schema = """
    CREATE TABLE meta (key TEXT, value TEXT);
    INSERT INTO meta VALUES ('version', '24');
    CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB,
                          expires_utc INTEGER, last_access_utc INTEGER, path TEXT);
    INSERT INTO cookies VALUES ('.claude.ai', 'sessionKey', 'sk-ant-sid01-synthetic-fixture-value', X'', 0, 1, '/');
    INSERT INTO cookies VALUES ('.claude.ai', 'lastActiveOrg', 'fixture-organization', X'', 0, 1, '/');
    INSERT INTO cookies VALUES ('.other.invalid', 'sessionKey', 'sk-ant-sid01-wrong-host', X'', 0, 99, '/');
    INSERT INTO cookies VALUES ('.claude.ai', 'sessionKey', 'sk-ant-sid01-expired', X'', 1, 99, '/');
    INSERT INTO cookies VALUES ('.claude.ai', 'sessionKey', 'sk-ant-sid01-wrong-path', X'', 0, 99, '/other');
    """
precondition(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
sqlite3_close(database)
var cachedPassword: Data?
let result = try ClaudeDesktopSessionReader.readDatabase(databaseURL, allowPrompt: false, password: &cachedPassword)
verify(result["sessionKey"] == session, "host, expiry, and path selection")
verify(result["lastActiveOrganization"] == "fixture-organization", "organization cookie mapping")
verify(cachedPassword == nil, "plaintext fixtures require no Keychain access")
print("Claude Desktop native synthetic checks passed: \(checks)")
'''


def main() -> None:
    source_path = Path(__file__).resolve().parents[1] / "macos/Runner/MainFlutterWindow.swift"
    source = source_path.read_text()
    reader = source[source.index("private enum ClaudeDesktopSessionReader {"):]
    # Compile the production reader independently of Flutter and expose only its test entry points.
    reader = reader.replace("private static func decode", "static func decode")
    reader = reader.replace("private static func readDatabase", "static func readDatabase")
    imports = "import Foundation\nimport CommonCrypto\nimport CryptoKit\nimport LocalAuthentication\nimport Security\nimport SQLite3\n"
    with tempfile.TemporaryDirectory(prefix="llmquota-native-fixtures-") as directory:
        root = Path(directory)
        swift_path = root / "main.swift"
        executable = root / "reader-tests"
        swift_path.write_text(imports + reader + HARNESS)
        subprocess.run(
            ["xcrun", "swiftc", "-target", f"{platform.machine()}-apple-macos10.15",
             str(swift_path), "-o", str(executable)],
            check=True,
        )
        subprocess.run([str(executable), directory], check=True)


if __name__ == "__main__":
    main()
