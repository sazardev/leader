# Agente inline (`<leader>a`)

Acciones de **un solo disparo** sobre lo que estás viendo: una función, una clase o una selección. Sin chat, sin
sidebar, sin conversación. Cada acción tiene un prompt cerrado, un contexto acotado y una salida con formato fijo,
así que es predecible y barata. Teclas: [`CHEATSHEET.md`](../../CHEATSHEET.md) (menú **Agent**).

## Flujo

1. Pon el cursor dentro de una función (o selecciona líneas en visual) y pulsa `<leader>a` + la acción.
2. El código que se envía se resalta y a la derecha gira `⠋ implement · claude/haiku · 1.2s`.
3. El resultado aparece **en el código**, según la acción:

| Acción | Entrada | Resultado |
|---|---|---|
| `i` implement | función (su nombre, firma, doc o `TODO` son la especificación) + instrucción opcional | diff en línea: lo borrado en rojo, lo añadido en verde debajo. `⏎` acepta, `⎋` rechaza |
| `r` review | función o selección | hallazgos reales como **diagnósticos** en su línea (`◆`); `<leader>xd` muestra el detalle |
| `e` explain | función o selección | ventana junto al código, con streaming; se cierra sola al mover el cursor |
| `a` ask | tu pregunta (campo de texto) | ventana, igual que explain |
| `f` fix | los diagnósticos del LSP dentro del objetivo + pista opcional | diff con el cambio mínimo; sin diagnósticos, no hace nada |
| `d` docs | función + enfoque opcional | diff que solo añade/actualiza el comentario de documentación |
| `R` refactor | tu instrucción (campo de texto) | diff que aplica exactamente esa instrucción |
| `g` handoff | tu instrucción | manda `archivo:rango` + instrucción a un agente que ya corre en Herdr |

**El campo de instrucción es en línea** (como el inline chat de Zed o VS Code): se abre justo ENCIMA del código objetivo y
**empuja el código hacia abajo** en vez de taparlo, con una barra de acento, una cabecera (`✦ implement · claude/sonnet`) y
un placeholder. Crece al escribir (hasta 6 filas), `⏎` envía, `⎋` cancela (también si cambias de ventana), `⌃J` / `Alt+Enter`
hacen salto de línea y `↑`/`↓` (o `⌃P`/`⌃N`) recorren las instrucciones anteriores de esa acción, que se recuerdan entre
sesiones. En ventanas estrechas la pista de teclas se acorta sola. No hay autocompletado ni auto-cierre de comillas dentro.

**Instrucción**: `i`, `d` y `f` abren el campo y **Enter con el campo vacío corre sin instrucción**; si escribes algo, se añade
al prompt y manda sobre el comportamiento por defecto. Sirve para una `func main() {}` vacía ("lee un CSV y suma la columna
3"), para una función poco clara ("esto valida pedidos antes de cobrar; falta el caso de cupones") o para guiar un arreglo.
`a` ask y `R` refactor exigen el texto; `r` review y `e` explain corren al instante.

**Menú corto**: `i` implement, `d` docs, `r` review, `e` explain, `a` ask, `f` fix, `R` refactor, `g` hand off (solo dentro de
Herdr), `h` history, `m` model (principal, ligero y esfuerzo en un solo selector), `c` clear (descarta los hallazgos de este archivo), `x` stop (cancela lo que corre y descarta las propuestas
pendientes; **no** toca los hallazgos) y `l` last answer (reabre la última respuesta o propuesta rechazada). Aceptar y rechazar una propuesta no tienen
entrada de menú: son `⏎` y `⎋` sobre la propuesta.

**Aceptar es un solo cambio**: `u` lo deshace entero. Si editas el código mientras el agente trabaja, la propuesta
se **descarta** en vez de pisar tu cambio. Varias acciones pueden correr a la vez (no sobre el mismo bloque).

## Qué objetivo toma

Prioridad: **selección visual** (siempre líneas completas) > **función** bajo el cursor (con los comentarios
contiguos de encima, que son la especificación) > **clase** > **párrafo** de líneas alrededor del cursor (sirve para
una firma a medias: escribe `func ParseConfig(path string) (*Config, error)` y pulsa `<leader>ai`).
"Función/clase" es la definición de `af`/`ac` (textobjects de treesitter), para cualquier lenguaje con parser.
Más de `context.max_target_lines` (400) se rechaza: recortarlo rompería el reemplazo.

## Contexto (y por qué cuesta poco)

Cada acción pide proveedores; juntos tienen tope de `context.max_chars` (8000 caracteres), el objetivo va aparte:

| Proveedor | Qué aporta | Coste |
|---|---|---|
| `rules` | `settings.agent.rules` + `.agent.md` de la raíz del proyecto (tus convenciones) | texto |
| `types` | **la definición de los tipos que usa el objetivo** (campos de un struct, miembros de una clase/interfaz/enum/trait), para que el modelo no adivine `Note.Done` | local + LSP |
| `contracts` | si el objetivo es un **adaptador** (`PostgresOrderRepository`): el **puerto** que debe cumplir (con ruta), qué métodos ya existen y **cuáles faltan**, la **entidad** que el puerto nombra y, al implementar, **otra implementación del proyecto** como ejemplo de estilo (constructor, errores, mapeo) | rg + treesitter |
| `schema` | para un adaptador de persistencia: la **tabla real** de la entidad (migraciones SQL con sus `ALTER`/índices posteriores, o `schema.prisma`) y la base de datos que se usa: dialecto, driver, estilo de parámetros (`$1`, `?`, `@p1`) | rg + manifiestos |
| `diagnostics` | diagnósticos del LSP/linters dentro del objetivo, **cada uno con su línea de código** (el objetivo no va numerado) | local |
| `callees` | firma REAL de lo que el objetivo llama, pedida al LSP (hover); lo que no llegue en 700 ms se omite | LSP |
| `outline` | imports + primera línea de cada función (sin repetir los tipos que ya van en `types`) | local |

`types` es independiente del lenguaje (usa las mismas queries de treesitter que `af`/`ac`): Go (struct, interface, alias),
TypeScript (interface, class, type, enum), Python, Rust (un método de `impl Note` trae `struct Note`, no el `impl`), Java...
Un tipo del **mismo archivo** se lee al instante; uno de **otro archivo o paquete** se localiza con el LSP
(`textDocument/definition`) y se extrae del archivo de destino (solo del proyecto, no de dependencias). Los tipos de los
campos se siguen un nivel (`Tags []Tag`), y si el objetivo es un método de clase, se incluye la clase sin el propio método.
Tope: `context.types` (4) definiciones de `context.type_lines` (30) líneas.

Cada acción pide lo que necesita, **en orden de prioridad** (si el presupuesto aprieta, lo último se recorta):

| Acción | Contexto |
|---|---|
| implement | rules, contracts, schema, types, callees, outline, diagnostics |
| port | rules, contracts, schema, types, diagnostics |
| review | rules, diagnostics, contracts, schema, types, callees |
| fix | rules, **diagnostics**, findings, contracts, types, callees |
| refactor | rules, types, callees, outline |
| ask | rules, types, callees, outline, diagnostics |
| explain | rules, types, callees |
| docs | rules, types (documenta los campos y parámetros reales, sin pagar outline ni callees) |

**Transparencia (`note:`)**: tras el bloque de código el modelo puede añadir `note: ...` (máx. ~15 palabras) cuando asumió o
añadió algo que no estaba en el contexto, y `needs-import: ...`. Ambos salen en la pista de la propuesta (`note: Note has no
Done field; assumed one`) y quedan en el historial. Medido en una prueba con `SetDone` sin `types`: adivinó `Done` y `Updated` y lo avisó;
con `types`: el mismo código, sin aviso, **-70 % de tokens de salida y -25 % de coste**.

**Medido con Claude**: una llamada normal de `claude -p` arrastra ~46 000 tokens de entrada (tus plugins, skills, hooks
y memoria). Con `--setting-sources ""`, `--tools ""` y `--system-prompt` propio baja a **~600 tokens** (+ el contexto), unos
2 s y fracciones de centavo por acción (haiku). Los CLIs corren en un directorio neutro (`stdpath("cache")/agent`), así que
tampoco cargan el `AGENTS.md`/`CLAUDE.md` de tu repo. Por eso **no se usa `--bare`**: rompería el login por suscripción.

**Auditoría de coste (medida)**: cada llamada de `claude -p` se facturaba como una *escritura* de caché de 1 hora (hasta 2× el
precio de entrada) y nunca acertaba en la caché, porque el mensaje cambia en cada llamada. Con `DISABLE_PROMPT_CACHING=1`
(ajuste `agent.claude.prompt_cache = false`, el valor por defecto) una acción de Sonnet pasó de **$0.0065 a $0.0037** y una de
Haiku de $0.0005 a $0.0003, sin cambio de latencia. Los prompts de sistema también se acortaron ~35 % (implement 1462 → 943 caracteres) y ahora dicen qué es verdad (`types`, `callees`, `diagnostics`) y que se avise con `note:` lo que se asumió. En total, la misma
acción cuesta **~50 % menos** que antes de la auditoría. Quedan ~560 tokens de entrada fijos del propio CLI que ninguna
bandera segura recorta (`CLAUDE_CODE_SIMPLE` y `--bare` rompen el login por suscripción). `agent.claude.max_cost_usd`
(0.25) corta una llamada desbocada.

## Modelos por tier (barato donde basta)

Cada acción corre en el modelo **principal** o en el **ligero**. `docs` y `explain` son ligeras (Claude: `haiku`); el resto
usa el principal (`sonnet` por defecto). Medido con Claude, una acción de una función: **~$0.005 en sonnet vs ~$0.0003 en
haiku**, unas 17 veces menos, y el spinner muestra el modelo que está corriendo. Las acciones ligeras tampoco heredan el
esfuerzo: son las baratas y no deben salir caras por un ajuste pensado para otras.

- `<leader>am` abre un selector con el modelo **principal** (y el backend), el modelo **ligero** y el esfuerzo, con su valor actual. Todo se recuerda.
- Cambiar qué acciones son ligeras: `agent = { tiers = { review = "light", docs = "main" } }` en `local.lua`.
- `agent.claude.light_model` / `agent.opencode.light_model` fijan el ligero por defecto. En OpenCode es `nil` (usa el
  principal) porque sus ids dependen de tu proveedor: elígelo en `<leader>am`.

## Backend y modelo

`<leader>am` → Main model abre UNA lista fuzzy con los modelos de todos los backends instalados (Claude: `haiku`/`sonnet`/`opus`;
OpenCode: lo que devuelva `opencode models`). Elegir uno cambia también de backend y **se recuerda** entre sesiones
(`stdpath("state")/agent.json`). El esfuerzo (solo Claude; `--effort`) está en el mismo selector. Con `backend = "auto"` se usa el
primero disponible de `agent.order`.

- **Claude Code** (`claude -p`): sin herramientas, sin sesión en disco, streaming de texto.
- **OpenCode** (`opencode run`): cada acción viaja como un agente efímero sin herramientas (`OPENCODE_CONFIG_CONTENT`).
  Arranca lento (~4 s): con `agent.opencode.attach = "http://localhost:4096"` (un `opencode serve` ya corriendo) se evita.
  `agent.opencode.agent` usa un agente tuyo. Si opencode no encuentra el agente pedido avisa y cae al de por defecto, que
  SÍ tiene herramientas: aquí eso se trata como error.
- Cada sesión de opencode queda en su lista con el título `nvim <acción>`.

## Backends y modelos locales (setup automático)

Además de Claude Code y OpenCode, el agente habla con **modelos locales** (Ollama en CPU o CUDA, LM Studio, llama.cpp,
vLLM...) y con cualquier otro CLI de agente (Hermes Agent, Gemini CLI, Codex, Aider). Un setup los detecta y los conecta.

**Arranque rápido**

1. `<leader>am` → **Setup** (o `scripts/agent-setup.sh` desde la terminal). Detecta en paralelo, sin tocar nada: los CLIs
   instalados, Ollama y los servidores OpenAI-compatibles (también el de **Windows si estás en WSL**: prueba `127.0.0.1`, el
   nameserver y la puerta de enlace), sus modelos, si lo cargado corre en **GPU o CPU**, la VRAM/RAM, y recuerda el servidor
   encontrado.
2. **Use detected models** aplica la recomendación con lo que ya tienes. Si no hay modelos, ofrece **Download** de un par
   según tu memoria (VRAM, o la mitad de la RAM sin GPU): `qwen2.5-coder` 32b/14b/7b/3b/1.5b. Son **sugerencias**, tú decides.
3. Si Ollama está instalado pero apagado: **Start Ollama server** (`ollama serve` en segundo plano). Arrancar y descargar
   siempre se piden explícitamente: nada se instala ni se descarga solo.

**Terminal** (`scripts/agent-setup.sh`; sin banderas solo informa y sale con 0 si hay un backend listo):

| Bandera | Hace |
|---|---|
| `--start` | arranca `ollama serve` si no responde |
| `--pull MODELO` | descarga un modelo (repetible) |
| `--auto` | aplica la recomendación con los modelos ya instalados |
| `--use backend/modelo[@light]` | fija backend y modelo (principal, o ligero con `@light`) |
| `--json` | la foto completa, para otras herramientas |

Ejemplo: `scripts/agent-setup.sh --start --pull qwen2.5-coder:3b --auto`.

**Lo mejor de cada nivel**: el principal sigue en Claude y los modelos locales cubren el **ligero** (`docs`, `explain`):
`light_backend` (en `<leader>am` → Light model, o `agent.light_backend`) deja esas acciones en un modelo local gratis sin
mover `implement`/`fix`/`review`. Sin ningún CLI de nube, el local pasa a ser también el principal.

**Backends** (todos usan `curl`, sin dependencias):

- `ollama`: `agent.ollama = { host, model, light_model, models, num_ctx, max_ctx, keep_alive, temperature, think }`. El host sale
  de `host` > `OLLAMA_HOST` > lo que detectó el setup > `127.0.0.1:11434`. `num_ctx` es **automático** (potencia de dos según
  el prompt, tope `max_ctx`): Ollama trunca EN SILENCIO lo que no cabe en su ventana y perdería justo las reglas del
  principio. `keep_alive` deja el modelo cargado (la primera acción tarda, las siguientes no); `temperature` baja (0.1)
  porque el formato exigido se respeta mejor. Coste siempre 0. Los `<think>…</think>` de qwen3/deepseek-r1 se descartan.
- `openai`: `agent.openai = { base_url, api_key_env, model, light_model, models, temperature }` (LM Studio `:1234`, llama.cpp
  `:8080`, vLLM `:8000`, LiteLLM, OpenRouter...). La clave se lee de la variable `api_key_env` y viaja por el entorno del
  proceso, no en los argumentos (no sale en `ps`).
- `custom` (Hermes Agent, Gemini CLI...): una entrada declarativa en `agent.custom`, sin escribir código:

```lua
-- local.lua
return { agent = { custom = {
  hermes = {
    label = "Hermes Agent",
    cmd = { "hermes", "chat", "-q", "{prompt}" },   -- {prompt} {system} {model}
    system_in_prompt = true,
    model_flag = { "-m", "{model}" },
    models = { "hermes3" },
  },
} } }
```

Las banderas del ejemplo de Hermes Agent **no están verificadas** (el CLI no estaba instalado al escribir esto): revísalas con
`hermes --help`. Los *modelos* Hermes sí funcionan hoy vía Ollama (`ollama pull hermes3`).

**Trampas**

- Un modelo local pequeño falla más con el formato estructurado (bloque de código, `L<n>|sev|msg`): úsalo en `docs`/`explain`
  y, si quieres más, sube a un modelo de código de 14b+. El `Esc` rechaza lo mal formado como siempre.
- Sin GPU el modelo corre en CPU: para el nivel ligero va bien; el informe indica si lo cargado está en GPU, GPU+CPU o CPU.
- WSL2: para llegar al Ollama de Windows ponle `OLLAMA_HOST=0.0.0.0` allí. En Docker con NVIDIA:
  `docker run -d --gpus all -p 11434:11434 -v ollama:/root/.ollama ollama/ollama`.
- El setup (y el informe de terminal) guarda en `agent.json` los servidores que encuentra (`endpoints`).

## Handoff a Herdr

`<leader>ah` (solo dentro de Herdr): escribes la instrucción, eliges un agente de `herdr agent list` (los de esta
carpeta primero) y se envía `archivo:rango` + diagnósticos con `herdr agent prompt`. Con cambios sin guardar adjunta el
código actual. Úsalo cuando la tarea ya no cabe en un disparo.

## Niveles de la arquitectura hexagonal (un menú por nivel)

`<leader>a` se queda con lo genérico (implement, review, explain, ask, fix, docs, refactor, hand off, model, history, clear, stop, last).
Cada **nivel** de la arquitectura tiene su carpeta (`lua/agent/<nivel>/`), su registro de acciones y su menú propio, con su contexto y,
en cada uno, un **análisis local de 0 tokens**. Las acciones de cada nivel corren por el mismo pipeline (diff en línea, hallazgos,
historial y coste), y en el historial aparecen con su nombre (`repo_port`, `service_review`, `ddd_fix`...).

| Menú | Nivel | Acciones con LLM | Análisis local (0 tokens) | Contexto propio |
|---|---|---|---|---|
| `<leader>aD` | **Dominio / DDD** (`agent/ddd/`) | implement `i`, review `r`, fix `f`, missing `m`, ask `a` | diagnose `d` (capas, violaciones, agregados), clear `c` | `ddd` (capas, nomenclatura, piezas relacionadas) |
| `<leader>aP` | **Repository** (`agent/repository/`) | port `p`, implement `i`, review `r` | **check** `c` (puerto vs métodos, entidad vs tabla) | `contracts`, `schema` |
| `<leader>aS` | **Service** (`agent/service/`) | implement `i`, review `r` | **deps** `d` (puertos que usa, llamadas inexistentes, implementaciones, cableado) | `ports` |

Los proveedores de cada nivel (`contracts`, `schema`, `ports`, `ddd`) son **silenciosos si el código no es de ese nivel**, así que
`implement`/`review`/`fix` del menú genérico también los reciben cuando aplica, sin pagar nada cuando no. El código compartido
(buscar con ripgrep, leer una definición de tipo) vive en `agent/discovery.lua`, para que los niveles no dependan entre sí.

## Repository (`<leader>aP`): adaptadores de persistencia

Implementar un repositorio (SQL, Postgres, MySQL, en memoria...) es largo pero mecánico, y el modelo necesita lo que **no está en el
archivo que ves**. El agente lo busca solo, sin que menciones archivos, y cada pieza llega **con su ruta**:

- **Puerto**: el interface que debe cumplir. Se deduce del nombre (`PostgresOrderRepository`, `pgOrderRepository`,
  `OrderRepositoryImpl`, `CachedOrderRepository` → `OrderRepository`) y de lo declarado a las claras (`implements X`, `class T(X)`,
  `impl X for T`, `var _ X = (*T)(nil)`); se localiza con ripgrep en **cualquier estructura de carpetas** y se lee con treesitter.
- **Qué falta**: compara los métodos del puerto con los que el tipo ya tiene (en Go, las funciones con ese receptor del paquete)
  y avisa también del constructor. Solo se piden los que faltan.
- **Entidad y tipos que el puerto nombra** (`Order`, con sus campos y sus constantes) aunque el struct vacío no los mencione:
  sin esto el modelo inventa los campos.
- **Ejemplo hermano**: otra implementación del proyecto (se prefiere la de la misma carpeta) con el constructor y el método
  equivalente: así copia tu estructura, tu manejo de errores (`fmt.Errorf("…: %w")`, `errors.Is(err, sql.ErrNoRows)`) y tu mapeo.
- **Esquema**: la tabla real de la entidad con sus cambios posteriores y el **dialecto** (de la sintaxis del esquema y de
  `go.mod`/`package.json`/`pyproject`/`Cargo.toml`/`pom.xml`), la librería de acceso y el estilo de parámetros. Es **agnóstico**: con
  el mismo prompt, una migración de Postgres produce `$1` y `ON CONFLICT`, y una de MySQL, `?` y `ON DUPLICATE KEY UPDATE`.

`<leader>aPp` (**repo port**) usa el tipo bajo el cursor (o el de su receptor, si estás dentro de uno de sus métodos) y escribe el tipo,
el constructor y TODOS los métodos que faltan, en el orden del puerto. `<leader>aPi` (repo implement) escribe un solo método con ese contexto; `implement` (`i`/`aDi`) lo recibe también si el código es un
adaptador, y `<leader>aPr` (repo review) revisa lo propio de la persistencia (columnas que no cuadran, parámetros del dialecto, SQL concatenado, `rows` sin cerrar,
errores sin envolver, N+1) y `<leader>aPc` (**repo check**, 0 tokens) compara los métodos del puerto con los del tipo y los campos de la entidad con las columnas de su tabla. **Silencioso si no aplica**:
un servicio, un handler o una función cualquiera no pagan ni la búsqueda (se mide: 0 caracteres de contexto extra).

Probado con Claude sobre un `PostgresOrderRepository` vacío con un puerto de 4 métodos: devolvió constructor y los 4 métodos con las
columnas reales de la migración, `$1…`, el estilo de errores de la implementación hermana y sin campos inventados (lo que asumió, como
`order.ErrNotFound`, lo dice en `note:`), por ~$0.0013 con Haiku. **Límites**: el puerto se encuentra por nombre o declaración
explícita (no por inferencia de tipos); el ejemplo hermano es el primero razonable que encuentra; el esquema solo se lee de `*.sql` y
`*.prisma` (no de modelos de un ORM ni de la base de datos viva).

## Service (`<leader>aS`): servicios de aplicación / casos de uso

Un servicio solo puede llamar a los métodos que sus **puertos** declaran. El proveedor `ports` encuentra las interfaces que el servicio recibe
(campos, parámetros del constructor, parámetros del método, en cualquier lenguaje) y las lee con sus firmas reales, cada una con su ruta y la
indicación de llamar solo a esos métodos; con `examples` añade otro servicio del proyecto como ejemplo de estilo.

- **`<leader>aSi` service implement**: orquesta el dominio y llama SOLO a los puertos de `<ports>` con sus nombres y firmas exactos; las reglas de
  negocio las llama en la entidad (no las reimplementa); propaga el contexto y traduce los errores de los puertos.
- **`<leader>aSr` service review**: llamadas a métodos de puerto que no existen o con argumentos erróneos, reglas de negocio en el servicio, detalles
  de infraestructura que se filtran, errores tragados o sin traducir, pasos no atómicos u ordenados de forma arriesgada (efectos antes de guardar), N+1.
- **`<leader>aSd` service deps** (0 tokens): por cada puerto, qué métodos declara, **cuáles llama este archivo y cuáles NO declara el puerto** (no
  compilaría), qué implementaciones tiene y si alguna está cableada (usada fuera de su archivo); lista lo que hay que atender.

Probado con Claude: sobre un servicio que llamaba a `orders.FindByID` (el puerto declara `ByID`), `deps` lo detectó sin LLM y `service review` lo
marcó contra el puerto real; `service implement` usó solo `ByID`, `Save` y `Mailer.Send` y llamó a `o.Confirm()` de la entidad en vez de repetir la
regla (lo que asumió, como un método que la entidad no tiene, lo dijo en `note:`).

## Hallazgos que se quedan (y cómo arreglarlos)

Los hallazgos de `review` y `ddd review`, y las violaciones de `ddd diagnose`, son diagnósticos **por atender**: se guardan
(`stdpath("state")/agent-findings.json`) y **vuelven al abrir el archivo en otra sesión**, aunque no los atiendas hoy.

- Cada uno se guarda con el **texto de la línea señalada**. Si el código se movió desde entonces (editaste encima, otra
  rama...), se **reubica** por ese texto (hasta ±40 líneas); si la línea ya no existe, se descarta con un aviso
  (`Agent: 1 saved finding no longer matches the code and was dropped`). Al guardar el archivo se actualizan las posiciones.
- Solo se guardan los del agente: los del LSP no se tocan. Si no hay archivo de hallazgos, abrir un archivo no cuesta nada.
- **`<leader>ac` clear** descarta los de este archivo (de la memoria y del disco); `<leader>aDc` ddd clear, los del diagnóstico de
  DDD de todo el proyecto. **`<leader>ax` stop no los borra**: solo cancela lo que corre y descarta propuestas pendientes.
- **Arreglarlos**: `<leader>af` (fix) y `<leader>aDf` (**ddd fix**) leen los hallazgos que caen en la función o selección,
  junto con los diagnósticos del LSP, y proponen el cambio mínimo (en `ddd fix`, respetando las capas de `<ddd>`; si el arreglo
  necesita un puerto, tipo o archivo que no existe, lo dice en `note:` y no inventa su contenido). Al **aceptar** la propuesta, los
  hallazgos de ese rango se dan por resueltos y desaparecen también de lo guardado. `review` y `ddd review` **no** leen hallazgos
  anteriores: un review nuevo no debe partir de lo que dijo el anterior.
- Flujo: `<leader>aDr` (review) → mañana, otra sesión: los diagnósticos siguen ahí → `<leader>aDf` sobre la función → `⏎`.

## DDD (`<leader>aD`)

Una función **aparte** del agente normal, con su menú, su registro de acciones (`lua/agent/ddd/`) y su contexto. Mismo
pipeline y misma experiencia (diff en línea, hallazgos como diagnósticos, ventana, historial y coste, donde se distinguen
como `ddd_implement`, `ddd_review`...), pero las acciones siguen las **capas y la nomenclatura de TU proyecto**.

| Tecla | Acción | Cuesta |
|---|---|---|
| `<leader>aDd` | **diagnose**: análisis estático de todo el proyecto | 0 tokens |
| `<leader>aDi` | implement: escribe el código en la capa que le toca, con tus nombres y el modismo del lenguaje | LLM |
| `<leader>aDr` | review: violaciones de DDD y SOLID como diagnósticos (sin repetir las que ya detectó el análisis local) | LLM |
| `<leader>aDf` | **fix**: arregla lo que `ddd review` y el diagnóstico dejaron por atender (cambio mínimo, respetando las capas) | LLM |
| `<leader>aDm` | missing: qué falta alrededor de lo que ves (puertos, implementaciones, casos de uso, DTOs, **cableado**, errores, tests), con nombres de archivo según tu convención | LLM |
| `<leader>aDa` | ask: pregunta de arquitectura con las capas y piezas reales | LLM |
| `<leader>aDc` | clear: descarta las violaciones del diagnóstico de todo el proyecto (también de lo guardado) | 0 tokens |

**Qué hace el análisis local (gratis, sin LLM)**: recorre el proyecto una vez (asíncrono, por tandas; solo lee los archivos
**dentro de directorios de capa** y que no sean tests; caché por mtime) y deduce:

- **Capas** por nombre de directorio (`domain`, `application`, `infrastructure`, `interface` y sinónimos: `usecases`, `adapters`,
  `persistence`, `api`, `handlers`...; ajustable en `settings.agent.ddd.layers`). La regla de dependencia apunta hacia dentro:
  dominio ← aplicación ← infraestructura / interfaz. Las raíces de composición (`main`, `cmd/`, `container`, `di`...) pueden cablear todo.
- **Violaciones** (diagnósticos `◈` en el código + lista de quickfix + panel): dependencias hacia fuera (con el import exacto),
  **frameworks en dominio/aplicación** (`database/sql`, `net/http`, `gorm`, `@nestjs`, `sqlalchemy`, `org.springframework`... por
  lenguaje: Go, TS/JS, Python, Java/Kotlin/Scala, Rust, C#, PHP, Dart) y archivos mal nombrados (`PaymentService` en `pricing.go`).
  Solo se capas los imports **del propio proyecto** (módulo de `go.mod`, relativos en TS/Python, `crate::` en Rust): `database/sql` es un framework, no "la capa database".
- **Nomenclatura**: estilo de archivos (`snake_case`, `kebab-case`, `order.entity.ts`, `PascalCase`) y roles más usados
  (`repository`, `service`, `handler`...), deducidos de lo que ya existe; las sugerencias de archivos faltantes la respetan.
- **Agregados, huecos y conexiones**: por entidad del dominio (tipo con campo `ID`) busca su **puerto** de repositorio, su
  **implementación**, si está **cableada** (su nombre se usa en algún otro archivo, vía `rg`) y sus **casos de uso**; lista lo que falta.

**Lo que recibe el modelo** (sección `<ddd>`, máx. 1800 caracteres, solo lo relevante para ese objetivo): su capa y de quién
puede depender, capas del proyecto, convención de nombres con ejemplos, archivos vecinos, las piezas que rodean a las entidades
que toca (`Order: port OrderRepository (...) · impl PostgresOrderRepository (...) wired ✓ · use cases PlaceOrder`), las violaciones
de ese archivo y **una línea con el modismo del lenguaje en curso** (constructores, errores, inyección). Más las reglas de DDD (~600 caracteres).

Medido en un proyecto Go con una entidad completa (puerto + implementación + caso de uso) y otra sin puerto: `implement` de
`Order.Confirm()` usó `Pending`/`Confirmed` (las constantes del tipo `Status` viajan con él) y respetó la capa; `review` encontró el
`*sql.DB` y el repositorio concreto metidos en la entidad, más primitivos sin invariante; `missing` listó la porción vertical de
`Customer` con rutas en el estilo del proyecto. Cada acción, por debajo de $0.001 con Haiku. En un repo de 7500 archivos de código, el
primer análisis tarda ~0.9 s (252 archivos de capa) y el siguiente 35 ms.

**Límites**: las capas se reconocen por nombre de directorio (si los tuyos se llaman distinto, ajusta `layers`); "entidad" es un tipo
del dominio con campo `ID`; "cableada" es "su nombre aparece en otro archivo", no un análisis del grafo de dependencias; los imports
se leen con regex y los tipos con treesitter, así que no es un compilador. Los lenguajes sin parser de treesitter solo aportan imports.

## Historial y gasto (`<leader>ah`)

Cada acción se guarda en `stdpath("state")/agent-history.jsonl` (solo-añadir): cuándo, acción, modelo, objetivo, **tu
instrucción, el prompt de sistema, el mensaje exacto enviado, la respuesta**, tokens (con lectura/escritura de caché), coste,
tiempo y **qué hiciste con el resultado** (aceptada, rechazada, descartada, N hallazgos...). Así ves con transparencia qué se
pidió y qué se pagó.

- `<leader>ah` abre un selector con una fila por ejecución (fecha, resultado, acción, modelo, coste, objetivo); el título
  suma el total gastado. La vista previa muestra todo el detalle; `⏎` lo abre en grande.
- `⌃S` abre el **informe de gasto**: por periodo (hoy, 7 días, total), por acción, por modelo, por día, **coste por cambio
  aplicado**, lo gastado en propuestas que no aplicaste, errores, aciertos de caché, **dónde se va el prompt** (system,
  contexto por proveedor, objetivo) y las 5 ejecuciones más caras. Es la base para decidir qué recortar.
- `⌃Y` **copia TODO lo de la ejecución** (el mismo texto que ves en el detalle): resultado y línea de eventos (aceptada a
  las 09:38:27...), objetivo, tiempo, tokens, coste, tu instrucción, la respuesta, el prompt de sistema y el mensaje
  exacto enviado. `⌃P` copia solo el prompt (sistema + mensaje) para reproducirlo o ajustarlo. En el panel de detalle y en
  el de informe, `Y` copia todo el panel. Todo va al portapapeles (`+`) y al registro sin nombre.
- Privacidad: el historial incluye tu código (va dentro del prompt). `agent.history.store_text = false` guarda solo métricas;
  `enabled = false` lo apaga. Se compacta solo a las `max_entries` (1000) más recientes.

## Convenciones del proyecto: `.agent.md`

Un `.agent.md` en la raíz (o hacia arriba) se añade a TODOS los prompts: estilo, librerías preferidas, qué evitar. Máx.
1500 caracteres útiles. Ejemplo: `Go idiomático; errores con %w; sin logs en funciones puras; tests con testify.`

## Ajustes (`settings.agent`, sobreescribibles en `local.lua`)

`backend`, `order`, `light_backend`, `history`, `language` (de explicaciones, respuestas y hallazgos; por defecto `English`), `rules`, `timeout_ms`, `tiers`, `context.*`, `apply.format`
(formatea el rango con conform al aceptar), `keys` (aceptar/rechazar), `claude.models`/`model`/`light_model`/`prompt_cache`/`max_cost_usd`, `opencode.*`, `ollama.*`, `openai.*`, `custom`.

## Extender

| Quiero... | Haz |
|---|---|
| otro backend (otro CLI) | `lua/agent/backends/<n>.lua` con el contrato de `backends/init.lua` + `NAMES`; sin código: una entrada en `agent.custom` |
| otra acción | `lua/agent/actions/<n>.lua` con el contrato de `actions/init.lua` + `NAMES`; el menú y el cheatsheet salen solos |
| otro tipo de salida | `lua/agent/output/<n>.lua` (`done` y opcional `stream`/`release`) + `NAMES` |
| otro proveedor de contexto | `lua/agent/context/providers/<n>.lua` (`cap`, `collect(target, done)`) y úsalo en `context` de una acción |

El formato que el modelo debe devolver (bloque de código, `L<n>|sev|msg`) vive en `lua/agent/protocol.lua` junto a su
parser: las reglas del prompt y su lectura cambian siempre juntas.

## Trampas

- Si el modelo desobedece y manda varios bloques de código (borrador + versión corregida, 2 de cada 6 veces en una prueba
  con Rust), se usa el **último que empieza como el objetivo** y la pista avisa: `model sent 2 blocks, check the diff`.
- La pista de aceptar/rechazar se acorta en ventanas estrechas (descarta primero tokens/coste) y el spinner pasa a versión compacta.
- Los colores del diff, el spinner, la pista y la ventana **se derivan de la paleta del tema activo** con contraste mínimo
  garantizado (4.5:1 para texto) y se recalculan al cambiar de tema (`<leader>S`); probados con los 97 temas de base46 y el
  tema heredado de la terminal. Los hallazgos usan los colores de diagnóstico de tu tema.
- La selección visual se toma como **líneas completas**.
- `Esc` rechaza la propuesta mientras hay una visible en el buffer (solo ahí; `settings.agent.keys` lo cambia).
- Un modelo puede devolver el bloque vacío: significa borrar ese rango (p. ej. `fix` quitando imports sin usar).
- `needs-import:` tras el bloque se muestra en la pista; los imports no se añaden solos.
- `scripts/test-agent.sh` corre las pruebas de parsers, objetivo, backends locales y setup (sin red ni tokens: los servidores de Ollama/OpenAI son falsos, `scripts/fake-llm.py`).
