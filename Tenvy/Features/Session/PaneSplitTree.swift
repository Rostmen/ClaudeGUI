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

// MARK: - PaneSplitTree

/// A recursive binary tree of terminal panes.
///
/// Each leaf holds a `ClaudeSession`; each split holds two subtrees plus a
/// draggable ratio (0…1). Splitting a leaf replaces that leaf with a split
/// node — all other parts of the tree are untouched, matching Ghostty's
/// native split behaviour.
struct PaneSplitTree {

  var root: Node

  // MARK: - Node

  indirect enum Node {
    case leaf(ClaudeSession)
    case split(Split)
  }

  // MARK: - Split

  struct Split {
    let id: UUID
    let direction: SplitViewDirection
    var ratio: Double   // 0…1 — where the divider sits
    var left: Node      // left pane (horizontal) or top pane (vertical)
    var right: Node     // right pane (horizontal) or bottom pane (vertical)
  }

  // MARK: - Init

  init(_ session: ClaudeSession) {
    root = .leaf(session)
  }

  private init(root: Node) {
    self.root = root
  }

  // MARK: - Accessors

  /// All sessions in leaf order (left-to-right / top-to-bottom).
  var allSessions: [ClaudeSession] { root.allSessions }

  /// Whether the tree contains a leaf with the given session ID.
  func contains(sessionId: String) -> Bool {
    root.contains(sessionId: sessionId)
  }

  // MARK: - Mutations

  /// Split the pane holding `atSessionId` in the given direction, placing
  /// `newSession` on the new side.  Returns `self` unchanged if `atSessionId`
  /// is not found.
  func inserting(_ newSession: ClaudeSession, at sessionId: String, direction: SplitDirection) -> PaneSplitTree {
    PaneSplitTree(root: root.inserting(newSession, at: sessionId, direction: direction) ?? root)
  }

  /// Remove the leaf holding `sessionId`.
  /// Returns `nil` if the last leaf was removed.
  func removing(sessionId: String) -> PaneSplitTree? {
    switch root {
    case .leaf(let s) where s.id == sessionId:
      return nil
    default:
      guard let newRoot = root.removing(sessionId: sessionId) else { return nil }
      return PaneSplitTree(root: newRoot)
    }
  }

  /// Update the ratio of the split identified by `splitId`.
  func updatingRatio(splitId: UUID, ratio: Double) -> PaneSplitTree {
    PaneSplitTree(root: root.updatingRatio(splitId: splitId, ratio: ratio))
  }

  /// Replace the leaf holding `sessionId` with `newSession` (used for sync).
  func replacing(sessionId: String, with newSession: ClaudeSession) -> PaneSplitTree {
    PaneSplitTree(root: root.replacing(sessionId: sessionId, with: newSession))
  }
}

// MARK: - Node helpers

private extension PaneSplitTree.Node {

  var allSessions: [ClaudeSession] {
    switch self {
    case .leaf(let s): return [s]
    case .split(let sp): return sp.left.allSessions + sp.right.allSessions
    }
  }

  func contains(sessionId: String) -> Bool {
    switch self {
    case .leaf(let s): return s.id == sessionId
    case .split(let sp): return sp.left.contains(sessionId: sessionId) || sp.right.contains(sessionId: sessionId)
    }
  }

  /// Returns the updated node, or `nil` if this node IS the target leaf.
  func inserting(_ newSession: ClaudeSession, at sessionId: String, direction: SplitDirection) -> PaneSplitTree.Node? {
    switch self {
    case .leaf(let session):
      guard session.id == sessionId else { return nil }
      let existing = PaneSplitTree.Node.leaf(session)
      let added    = PaneSplitTree.Node.leaf(newSession)
      let splitDir: SplitViewDirection = direction.isVertical ? .vertical : .horizontal
      let (left, right): (PaneSplitTree.Node, PaneSplitTree.Node) = direction.isReversed
        ? (added, existing)
        : (existing, added)
      return .split(PaneSplitTree.Split(
        id: UUID(),
        direction: splitDir,
        ratio: 0.5,
        left: left,
        right: right
      ))

    case .split(var sp):
      if let newLeft = sp.left.inserting(newSession, at: sessionId, direction: direction) {
        sp.left = newLeft
        return .split(sp)
      }
      if let newRight = sp.right.inserting(newSession, at: sessionId, direction: direction) {
        sp.right = newRight
        return .split(sp)
      }
      return nil
    }
  }

  /// Returns the updated node, or `nil` if this node was the removed leaf.
  func removing(sessionId: String) -> PaneSplitTree.Node? {
    switch self {
    case .leaf(let s):
      return s.id == sessionId ? nil : self

    case .split(var sp):
      if sp.left.contains(sessionId: sessionId) {
        if let newLeft = sp.left.removing(sessionId: sessionId) {
          sp.left = newLeft
          return .split(sp)
        } else {
          // Left subtree collapsed — replace this split with the right subtree.
          return sp.right
        }
      }
      if sp.right.contains(sessionId: sessionId) {
        if let newRight = sp.right.removing(sessionId: sessionId) {
          sp.right = newRight
          return .split(sp)
        } else {
          // Right subtree collapsed — replace this split with the left subtree.
          return sp.left
        }
      }
      return self
    }
  }

  func updatingRatio(splitId: UUID, ratio: Double) -> PaneSplitTree.Node {
    switch self {
    case .leaf:
      return self
    case .split(var sp):
      if sp.id == splitId {
        sp.ratio = ratio
        return .split(sp)
      }
      sp.left  = sp.left.updatingRatio(splitId: splitId, ratio: ratio)
      sp.right = sp.right.updatingRatio(splitId: splitId, ratio: ratio)
      return .split(sp)
    }
  }

  func replacing(sessionId: String, with newSession: ClaudeSession) -> PaneSplitTree.Node {
    switch self {
    case .leaf(let s):
      return s.id == sessionId ? .leaf(newSession) : self
    case .split(var sp):
      sp.left  = sp.left.replacing(sessionId: sessionId, with: newSession)
      sp.right = sp.right.replacing(sessionId: sessionId, with: newSession)
      return .split(sp)
    }
  }
}
