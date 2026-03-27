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
import UniformTypeIdentifiers
import AppKit

/// Service for exporting and importing Claude sessions
@MainActor
final class SessionExportService {
  static let shared = SessionExportService()

  private let fileManager = FileManager.default

  /// Custom UTType for exported sessions
  static let sessionArchiveType = UTType(exportedAs: "com.chatsessions.session-archive", conformingTo: .zip)

  private init() {}

  // MARK: - Export

  /// Export a session to a zip archive
  /// - Parameters:
  ///   - session: The session to export
  ///   - destinationURL: Where to save the zip file (if nil, shows save panel)
  /// - Returns: URL of the created zip file, or nil if cancelled/failed
  func exportSession(_ session: ClaudeSession, to destinationURL: URL? = nil) async throws -> URL? {
    guard let sessionFilePath = session.filePath else {
      throw ExportError.noSessionFile
    }

    // Determine destination
    let destination: URL
    if let dest = destinationURL {
      destination = dest
    } else {
      guard let url = await showSavePanel(for: session) else {
        return nil // User cancelled
      }
      destination = url
    }

    // Create temporary directory for archive contents
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? fileManager.removeItem(at: tempDir)
    }

    // Copy session file
    let sessionFileName = sessionFilePath.lastPathComponent
    try fileManager.copyItem(
      at: sessionFilePath,
      to: tempDir.appendingPathComponent(sessionFileName)
    )

    // Copy session folder if it exists (contains additional data)
    let sessionFolder = sessionFilePath.deletingPathExtension()
    if fileManager.fileExists(atPath: sessionFolder.path) {
      try fileManager.copyItem(
        at: sessionFolder,
        to: tempDir.appendingPathComponent(sessionFolder.lastPathComponent)
      )
    }

    // Create metadata file with project info
    let metadata = SessionExportMetadata(
      sessionId: session.id,
      title: session.title,
      projectPath: session.projectPath,
      workingDirectory: session.workingDirectory,
      exportDate: Date(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    )
    let metadataData = try JSONEncoder().encode(metadata)
    try metadataData.write(to: tempDir.appendingPathComponent("metadata.json"))

    // Create zip archive
    try createZipArchive(from: tempDir, to: destination)

    return destination
  }

  /// Show save panel for export
  private func showSavePanel(for session: ClaudeSession) async -> URL? {
    await withCheckedContinuation { continuation in
      let panel = NSSavePanel()
      panel.title = "Export Session"
      panel.nameFieldStringValue = sanitizeFileName(session.title) + ".clsession"
      panel.allowedContentTypes = [.zip]
      panel.canCreateDirectories = true

      if panel.runModal() == .OK {
        continuation.resume(returning: panel.url)
      } else {
        continuation.resume(returning: nil)
      }
    }
  }

  /// Create a zip archive from a directory
  private func createZipArchive(from sourceDir: URL, to destination: URL) throws {
    // Remove existing file if present
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }

    // Use ditto command to create zip (preserves metadata, handles large files well)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceDir.path, destination.path]

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw ExportError.zipCreationFailed
    }
  }

  // MARK: - Import

  /// Import a session from a zip archive
  /// - Parameters:
  ///   - archiveURL: URL of the zip file to import
  ///   - sessionManager: Session manager to add the imported session to
  /// - Returns: The imported session, or nil if failed
  func importSession(from archiveURL: URL, sessionManager: any SessionDiscovery) async throws -> ClaudeSession? {
    // Create temporary directory for extraction
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? fileManager.removeItem(at: tempDir)
    }

    // Extract zip archive
    try extractZipArchive(from: archiveURL, to: tempDir)

    // Find the extracted content directory (ditto creates a parent folder)
    let extractedContents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
    let contentDir: URL
    if extractedContents.count == 1, extractedContents[0].hasDirectoryPath {
      contentDir = extractedContents[0]
    } else {
      contentDir = tempDir
    }

    // Read metadata
    let metadataURL = contentDir.appendingPathComponent("metadata.json")
    guard fileManager.fileExists(atPath: metadataURL.path) else {
      throw ImportError.missingMetadata
    }

    let metadataData = try Data(contentsOf: metadataURL)
    let metadata = try JSONDecoder().decode(SessionExportMetadata.self, from: metadataData)

    // Find session file
    let contents = try fileManager.contentsOfDirectory(at: contentDir, includingPropertiesForKeys: nil)
    guard let sessionFile = contents.first(where: { $0.pathExtension == "jsonl" }) else {
      throw ImportError.missingSessionFile
    }

    // Determine destination project directory
    let claudeProjectsPath = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")
    let encodedProjectPath = encodeProjectPath(metadata.projectPath)
    let projectDir = claudeProjectsPath.appendingPathComponent(encodedProjectPath)

    // Create project directory if needed
    try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

    // Use the ORIGINAL session ID - Claude CLI needs this to find the conversation
    let originalSessionId = metadata.sessionId
    let destinationFile = projectDir.appendingPathComponent("\(originalSessionId).jsonl")

    // Check if session already exists
    if fileManager.fileExists(atPath: destinationFile.path) {
      throw ImportError.sessionAlreadyExists
    }

    // Copy session file as-is (preserving original session ID)
    try fileManager.copyItem(at: sessionFile, to: destinationFile)

    // Copy session folder if present (with original name)
    let sessionFolder = sessionFile.deletingPathExtension()
    if fileManager.fileExists(atPath: sessionFolder.path) {
      let destFolder = projectDir.appendingPathComponent(originalSessionId)
      if !fileManager.fileExists(atPath: destFolder.path) {
        try fileManager.copyItem(at: sessionFolder, to: destFolder)
      }
    }

    // Create session object
    let importedSession = ClaudeSession(
      id: originalSessionId,
      title: metadata.title,
      projectPath: metadata.projectPath,
      workingDirectory: metadata.workingDirectory,
      lastModified: Date(),
      filePath: destinationFile
    )

    // Reload sessions to pick up the new one
    await sessionManager.loadSessions()

    return importedSession
  }

  /// Show open panel for import
  func showImportPanel() async -> URL? {
    await withCheckedContinuation { continuation in
      let panel = NSOpenPanel()
      panel.title = "Import Session"
      panel.allowedContentTypes = [.zip, Self.sessionArchiveType]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true

      if panel.runModal() == .OK {
        continuation.resume(returning: panel.url)
      } else {
        continuation.resume(returning: nil)
      }
    }
  }

  /// Extract a zip archive to a directory
  private func extractZipArchive(from archiveURL: URL, to destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archiveURL.path, destination.path]

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw ImportError.extractionFailed
    }
  }

  // MARK: - Helpers

  /// Encode a project path for use as a directory name
  private func encodeProjectPath(_ path: String) -> String {
    // Convert "/Users/foo/bar" to "-Users-foo-bar"
    return path.replacingOccurrences(of: "/", with: "-")
  }

  /// Sanitize a string for use as a filename
  private func sanitizeFileName(_ name: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    return name.components(separatedBy: invalidCharacters).joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)
  }

  /// Check if a URL is a valid session archive
  func isValidSessionArchive(_ url: URL) -> Bool {
    let validExtensions = ["zip", "clsession"]
    return validExtensions.contains(url.pathExtension.lowercased())
  }
}

// MARK: - Metadata

/// Metadata stored in exported session archives
struct SessionExportMetadata: Codable {
  let sessionId: String
  let title: String
  let projectPath: String
  let workingDirectory: String
  let exportDate: Date
  let appVersion: String
}

// MARK: - Errors

enum ExportError: LocalizedError {
  case noSessionFile
  case zipCreationFailed

  var errorDescription: String? {
    switch self {
    case .noSessionFile:
      return "Session has no file to export"
    case .zipCreationFailed:
      return "Failed to create zip archive"
    }
  }
}

enum ImportError: LocalizedError {
  case missingMetadata
  case missingSessionFile
  case extractionFailed
  case invalidArchive
  case sessionAlreadyExists

  var errorDescription: String? {
    switch self {
    case .missingMetadata:
      return "Archive is missing metadata file"
    case .missingSessionFile:
      return "Archive is missing session file"
    case .extractionFailed:
      return "Failed to extract archive"
    case .invalidArchive:
      return "Invalid session archive"
    case .sessionAlreadyExists:
      return "A session with this ID already exists"
    }
  }
}
