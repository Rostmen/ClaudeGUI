// MIT License
//
// Copyright (c) 2026 Rostyslav Kobizsky
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Security

/// Abstraction for keychain operations — injectable for testing.
protocol KeychainServiceProtocol {
  @discardableResult func save<T: Encodable>(_ value: T, account: String) -> Bool
  func load<T: Decodable>(_ type: T.Type, account: String) -> T?
  @discardableResult func delete(account: String) -> Bool
}

/// Stores and retrieves sensitive data from the macOS Keychain.
struct KeychainService: KeychainServiceProtocol {
  private let service: String

  init(service: String = "com.rostmen.Tenvy") {
    self.service = service
  }

  /// Saves a JSON-encodable value to the Keychain under the given account key.
  @discardableResult
  func save<T: Encodable>(_ value: T, account: String) -> Bool {
    guard let data = try? JSONEncoder().encode(value) else { return false }

    // Delete any existing item first
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    return status == errSecSuccess
  }

  /// Loads a JSON-decodable value from the Keychain for the given account key.
  func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  /// Deletes a Keychain item for the given account key.
  @discardableResult
  func delete(account: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
