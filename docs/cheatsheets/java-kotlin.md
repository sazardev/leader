# Java y Kotlin

Filetypes: `java`, `kotlin`. Comparten las mismas acciones (Gradle o Maven).

## Herramientas

| Qué | Con |
|---|---|
| Treesitter | `java`, `kotlin` |
| LSP / formatter / linter | **no hay declarados** en el registro; los menús corren las tareas de build |

> Para jdtls / kotlin-language-server, añádelos en `lua/languages/java.lua` y `kotlin.lua` (`lsp`, `mason`).

## Menús: `<leader>j` (Java) y `<leader>k` (Kotlin)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

Detecta el proyecto por `gradlew`, `build.gradle(.kts)`, `settings.gradle(.kts)` o `pom.xml`.
Usa los wrappers (`./gradlew`, `./mvnw`) si existen; si no, `gradle` / `mvn`. Si no hay proyecto Gradle/Maven, avisa en vez de fallar.

| Acción | Gradle | Maven |
|---|---|---|
| run | `run` | `spring-boot:run` si el `pom` usa Spring Boot; si no `compile exec:java` |
| build | `build` | `package` |
| test | `test` | `test` |
| check / verify | `check` | `verify` |
| clean | `clean` | `clean` |
