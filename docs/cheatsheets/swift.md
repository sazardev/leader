# Swift (Swift Package Manager)

Filetype: `swift`. Pack `swift`. For packages, CLIs and servers on Linux/WSL or macOS; Xcode projects are not covered.

## Tools

| What | With |
|---|---|
| LSP | `sourcekit-lsp` (from the toolchain; enabled only when it is on PATH) |
| Format on save | `swift format` (Swift 6 toolchains) |
| Lint | `swiftlint` when it is installed |
| Debug | `lldb-dap` (from the toolchain) |
| Treesitter | `swift` |

Nothing is downloaded for Swift: everything comes with the toolchain (https://swift.org/install).

## `<leader>i` menu (only in `*.swift`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do, at the package root (`Package.swift`):

- **SPM**: run, build (debug, release), format the whole package, swiftlint, package update/resolve/clean, open
  `Package.swift`.
- **Tests in the editor**: XCTest (`func test…()` in an `XCTestCase`, filter `CalcTests/testAdd`) and Swift Testing
  (`@Test` functions, `@Suite` types); the file runs its test types. Marks per test, failures as diagnostics on the line
  of the assertion (`XCTAssertEqual failed…`, `Expectation failed…`), the quickfix list. The file toggle jumps between
  `Sources/<Target>/X.swift` and `Tests/<Target>Tests/XTests.swift`.
- **Debug** (`<leader>iD`): the package's executable after `swift build`.
- **Setup** (`<leader>iS`): `.swift-format`, `.swiftlint.yml`, a server Dockerfile (static stdlib, slim runtime) and its
  `.dockerignore`, GitHub Actions on Linux (the `swift:<tools version>` image), `.editorconfig`, a Makefile preset,
  `.gitignore`.

## Snippets

`xctestcase`, `swifttest`, `swiftsuite`, `errorenum`.
