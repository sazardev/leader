# Java and Kotlin

Filetypes: `java`, `kotlin`. They share the same actions (Gradle or Maven).

## Tools

| What | With |
|---|---|
| Treesitter | `java`, `kotlin` |
| LSP / formatter / linter | **none declared** in the registry; the menus run the build tasks |

> For jdtls / kotlin-language-server, add them in `lua/languages/java.lua` and `kotlin.lua` (`lsp`, `mason`).

## Menus: `<leader>j` (Java) and `<leader>k` (Kotlin)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

It detects the project by `gradlew`, `build.gradle(.kts)`, `settings.gradle(.kts)` or `pom.xml`.
It uses the wrappers (`./gradlew`, `./mvnw`) if they exist; otherwise `gradle` / `mvn`. If there is no Gradle/Maven project, it warns instead of failing.

| Action | Gradle | Maven |
|---|---|---|
| run | `run` | `spring-boot:run` if the `pom` uses Spring Boot; otherwise `compile exec:java` |
| build | `build` | `package` |
| test | `test` | `test` |
| check / verify | `check` | `verify` |
| clean | `clean` | `clean` |
