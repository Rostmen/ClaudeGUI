import Foundation
@testable import Tenvy

/// In-memory keychain mock for testing. Tracks all save/load/delete calls.
final class MockKeychainService: KeychainServiceProtocol {
  private var storage: [String: Data] = [:]
  private(set) var saveCallCount = 0
  private(set) var loadCallCount = 0
  private(set) var deleteCallCount = 0

  @discardableResult
  func save<T: Encodable>(_ value: T, account: String) -> Bool {
    saveCallCount += 1
    guard let data = try? JSONEncoder().encode(value) else { return false }
    storage[account] = data
    return true
  }

  func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
    loadCallCount += 1
    guard let data = storage[account] else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  @discardableResult
  func delete(account: String) -> Bool {
    deleteCallCount += 1
    storage.removeValue(forKey: account)
    return true
  }
}
