import Foundation
import Security

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 4 else {
    fail("usage: keychain-helper {store|read-toml|delete} service account", code: 64)
}

let operation = CommandLine.arguments[1]
let service = CommandLine.arguments[2]
let account = CommandLine.arguments[3]
let lookup: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account
]

switch operation {
case "store":
    var passwordData = FileHandle.standardInput.readDataToEndOfFile()
    while passwordData.last == 10 || passwordData.last == 13 {
        passwordData.removeLast()
    }
    guard !passwordData.isEmpty else { fail("empty password", code: 65) }

    let attributes: [String: Any] = [
        kSecValueData as String: passwordData,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]
    let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
        var item = lookup
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { fail("keychain add failed: \(addStatus)") }
    } else if updateStatus != errSecSuccess {
        fail("keychain update failed: \(updateStatus)")
    }

case "read-toml":
    var query = lookup
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let password = String(data: data, encoding: .utf8) else {
        fail("keychain read failed: \(status)")
    }
    do {
        let encoded = try JSONSerialization.data(withJSONObject: [password])
        guard encoded.count >= 2 else { fail("password encoding failed") }
        FileHandle.standardOutput.write(encoded.subdata(in: 1..<(encoded.count - 1)))
    } catch {
        fail("password encoding failed: \(error.localizedDescription)")
    }

case "delete":
    let status = SecItemDelete(lookup as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        fail("keychain delete failed: \(status)")
    }

default:
    fail("unknown operation: \(operation)", code: 64)
}
