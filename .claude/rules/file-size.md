# File Size Limit — HARD RULE

No Swift file should exceed **800 lines of code**. The absolute ceiling is **1000 lines** — any file approaching this must be split immediately.

## How to keep files small

- Extract extensions into dedicated files: `TypeName+Purpose.swift` (one extension, one purpose per file)
- Extract standalone types (structs, enums) into their own files
- Extract pure/static helper functions as extensions on the relevant type (e.g., `DateFormatter+BranchName.swift`)
- Private helper functions used only by the extension can live in the same file
- Do NOT put multiple unrelated extensions in a single file

## When splitting a ViewModel or large class

- Keep stored properties, init/deinit, and core computed properties in the main file
- Group methods by responsibility into extension files (e.g., `+DragAndDrop`, `+SessionCreation`)
- Change `private` → `internal` for members accessed from extension files (acceptable for `final class` in app target)
