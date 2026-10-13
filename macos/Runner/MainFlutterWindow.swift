import Cocoa
import CommonCrypto
import CryptoKit
import FlutterMacOS
import LocalAuthentication
import Security
import SQLite3

class MainFlutterWindow: NSWindow {
    private var desktopChannel: FlutterMethodChannel?
    private let desktopQueue = DispatchQueue(label: "llmquota.claude-desktop")

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        RegisterGeneratedPlugins(registry: flutterViewController)

        let channel = FlutterMethodChannel(
            name: "llmquota/claude_desktop", binaryMessenger: flutterViewController.engine.binaryMessenger)
        desktopChannel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "readSession" else {
                result(FlutterMethodNotImplemented)
                return
            }
            let allowPrompt = (call.arguments as? [String: Any])?["allowPrompt"] as? Bool ?? false
            self?.desktopQueue.async {
                let response: Any
                do {
                    response = try ClaudeDesktopSessionReader.readSession(allowPrompt: allowPrompt)
                } catch let error as ClaudeDesktopSessionReader.ReadError {
                    response = FlutterError(code: error.rawValue, message: error.message, details: nil)
                } catch {
                    response = FlutterError(
                        code: "desktop_session_unavailable", message: "Claude Desktop session is unavailable.", details: nil)
                }
                DispatchQueue.main.async { result(response) }
            }
        }
        super.awakeFromNib()
    }
}

private enum ClaudeDesktopSessionReader {
    enum ReadError: String, Error {
        case missing = "desktop_session_missing"
        case unavailable = "desktop_session_unavailable"
        case keychain = "desktop_keychain_locked"
        case invalid = "desktop_session_invalid"

        var message: String {
            switch self {
            case .missing: return "Sign in to Claude Desktop before refreshing quota."
            case .unavailable: return "Claude Desktop cookies could not be read."
            case .keychain: return "Claude Desktop Safe Storage is not accessible without Keychain authorization."
            case .invalid: return "Claude Desktop session could not be decoded."
            }
        }
    }

    static func readSession(allowPrompt: Bool) throws -> [String: String] {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        var lastError: ReadError = .missing
        var password: Data?
        for relativePath in ["Cookies", "Network/Cookies", "Default/Cookies"] {
            let url = directory.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                return try readDatabase(url, allowPrompt: allowPrompt, password: &password)
            } catch let error as ReadError {
                lastError = error
                if error == .keychain { throw error }
            }
        }
        throw lastError
    }

    private static func readDatabase(
        _ url: URL, allowPrompt: Bool, password: inout Data?
    ) throws -> [String: String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw ReadError.unavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        var versionStatement: OpaquePointer?
        var version = 0
        if sqlite3_prepare_v2(database, "SELECT value FROM meta WHERE key = 'version'", -1,
                              &versionStatement, nil) == SQLITE_OK,
           let versionStatement, sqlite3_step(versionStatement) == SQLITE_ROW {
            version = Int(sqlite3_column_int(versionStatement, 0))
        }
        sqlite3_finalize(versionStatement)
        var statement: OpaquePointer?
        let query = """
            SELECT host_key, name, value, encrypted_value FROM cookies
            WHERE host_key IN ('.claude.ai', 'claude.ai') AND name IN ('sessionKey', 'lastActiveOrg')
            AND path = '/'
            AND (expires_utc = 0 OR expires_utc > (strftime('%s','now') + 11644473600) * 1000000)
            ORDER BY last_access_utc DESC
            """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let hostPointer = sqlite3_column_text(statement, 0),
                  let namePointer = sqlite3_column_text(statement, 1) else { continue }
            let host = String(cString: hostPointer)
            let name = String(cString: namePointer)
            guard values[name] == nil else { continue }
            var value = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            if value.isEmpty {
                let count = Int(sqlite3_column_bytes(statement, 3))
                guard count > 3, count < 16384, let bytes = sqlite3_column_blob(statement, 3) else { continue }
                if password == nil { password = try safeStoragePassword(allowPrompt: allowPrompt) }
                guard let password else { throw ReadError.keychain }
                value = try decode(Data(bytes: bytes, count: count), host: host, version: version, password: password)
            }
            guard value.utf8.count <= 8192,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ReadError.invalid
            }
            values[name] = value
        }
        guard let session = values["sessionKey"], session.hasPrefix("sk-ant-sid"), session.count >= 20 else {
            throw ReadError.missing
        }
        var result = ["sessionKey": session]
        if let organization = values["lastActiveOrg"], !organization.isEmpty {
            result["lastActiveOrganization"] = organization
        }
        return result
    }

    private static func safeStoragePassword(allowPrompt: Bool) throws -> Data {
        // Background refresh must not trigger an unexpected Keychain authentication prompt.
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = !allowPrompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecAttrAccount as String: "Claude Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let password = item as? Data else { throw ReadError.keychain }
        return password
    }

    private static func decode(_ encrypted: Data, host: String, version: Int, password: Data) throws -> String {
        guard encrypted.prefix(3) == Data("v10".utf8) else { throw ReadError.invalid }
        var key = Data(count: kCCKeySizeAES128)
        let salt = Data("saltysalt".utf8)
        let derivation = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128)
                }
            }
        }
        guard derivation == kCCSuccess else { throw ReadError.invalid }
        let ciphertext = Data(encrypted.dropFirst(3))
        let initializationVector = Data(repeating: 32, count: kCCBlockSizeAES128)
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let status = plaintext.withUnsafeMutableBytes { output in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    initializationVector.withUnsafeBytes { vector in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count,
                            vector.baseAddress, input.baseAddress, ciphertext.count,
                            output.baseAddress, output.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ReadError.invalid }
        plaintext.count = written
        if version >= 24 {
            // Chromium binds encrypted cookies to their host to prevent cross-domain substitution.
            let digest = Data(SHA256.hash(data: Data(host.utf8)))
            guard plaintext.count >= digest.count, plaintext.prefix(digest.count) == digest else {
                throw ReadError.invalid
            }
            plaintext = Data(plaintext.dropFirst(digest.count))
        }
        guard let value = String(data: plaintext, encoding: .utf8) else { throw ReadError.invalid }
        return value
    }
}
