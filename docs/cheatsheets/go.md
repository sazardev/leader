# Go

## Herramientas

| Qué | Con |
|---|---|
| LSP | gopls (gofumpt, staticcheck, placeholders, analyses: unusedparams, shadow, unusedwrite, useany; inlay hints) |
| Formato (al guardar y `<leader>fm`) | `goimports` y luego `gofumpt` |
| Lint | `golangci-lint` (en modo ligero: `go vet`); no corre al salir de insert |
| Extra | go.nvim (`GoAddTag`, `GoFillStruct`, `GoIfErr`, `GoAddTest`...), treesitter, gomodifytags |

## Menú `<leader>g` (solo en `*.go`)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

- Las acciones de struct (tags, rellenar literal, `if err`, añadir test) actúan sobre el cursor. Las de **tags** (`ga`/`gA`/`gD`) **guardan el archivo** al terminar (así lo hace go.nvim).
- En modo ligero go.nvim no carga: esas acciones avisan en vez de fallar.
- `run` y `build` corren sobre el directorio del archivo (`.` si hay `go.mod`, o el archivo suelto si no). El resto, desde la raíz del módulo.

## Tags de struct mientras escribes (`utils/gotags.lua`)

El valor del tag se **deriva del nombre del campo**: `SentAt` → `sent_at`, `UserID` → `user_id`, `HTTPServer` → `http_server`, `Kind` → `kind`.

| Escribes (en un campo de struct) | Sugiere |
|---|---|
| `` ` `` tras el tipo | `json:"kind"`, `json:"kind,omitempty"`, `json:"sentAt"` (camelCase si difiere), **las variantes de `gorm:"…"` para ese campo y su tipo** (ver abajo), yaml, db, mapstructure, form, toml, xml, `json:"-"`, `validate:"required"` |
| `json:` | `"kind"`, `"kind,omitempty"`, camelCase, `"-"` |
| `json:"` | `kind`, `kind,omitempty`, camelCase, `-` |
| `json:"kind,` | `omitempty`, `omitzero`, `string` (las opciones cambian según la clave) |
| `gorm:"` | valores completos según campo y tipo: `primaryKey;type:text`, `type:text;not null`… |
| `gorm:"type:text;` | opciones sueltas que aún no usaste: `not null`, `index`, `size:255`, `column:title`, `default:…`… |

```go
type Envelope struct {
    Kind   Kind      `json:"kind"`
    ID     string    `json:"id,omitempty"`
    SentAt time.Time `json:"sent_at"`
}
```

- Dentro de un tag **el primer ítem viene preseleccionado**: `Enter` lo acepta.
- El cursor queda **dentro de las comillas**: teclea `,` para las opciones, o `Tab` para salir.
- Salen solo las claves que aún no usaste en ese tag.
- No se activa en raw strings (`` query := `SELECT… ``), `return`, asignaciones, etc. (treesitter vigila que estés en un struct).

### gorm

gorm separa sus opciones con **`;`** (no con `,`) y algunas llevan valor (`size:255`, `column:sent_at`). Al abrir el tag `gorm:"` salen **valores completos** elegidos por el **nombre y el tipo del campo**; tras un `;` salen las **opciones sueltas** (las ya usadas no se repiten, y el cursor queda en el valor de `size:`, `type:`, `column:`… con Tab para saltar).

| Campo | Variantes que ofrece (en este orden) |
|---|---|
| `ID string` | `primaryKey;type:text`, `primaryKey`, `primaryKey;type:uuid` |
| `ID` entero | `primaryKey;autoIncrement`, `primaryKey` |
| `string` | `type:text;not null`, `type:text`, `not null`, `type:text;not null;index`, `uniqueIndex`, `index`, `size:255` |
| `CreatedAt` / `UpdatedAt` (`time.Time`) | `autoCreateTime` / `autoUpdateTime`, `not null;auto…`, `not null`, `index` |
| otro `time.Time`, `gorm.DeletedAt` | `not null`, `index` / `index` |
| `bool` | `not null;default:false`, `default:false`, `index` |
| enteros y floats | `not null`, `not null;default:0`, `default:0`, `index` |
| `[]byte` | `type:blob`, `type:bytea` |
| tipo propio o relación (`Author User`) | `foreignKey:AuthorID`, `embedded`, `many2many:author` |
| (todos) | `column:<nombre_en_snake>`, `-` |

Con un puntero (`*string`) no se ofrece `not null`. Los tags `gorm` salen **en cualquier archivo** `.go`.

```go
type NoteModel struct {
    ID        string    `gorm:"primaryKey;type:text"`
    Title     string    `gorm:"type:text;not null;index"`
    Content   string    `gorm:"type:text"`
    CreatedAt time.Time `gorm:"not null"`
}
```

### Archivos de modelo (`*_model.go` / `model.go`, `utils/gomodel.lua`)

Solo ahí salen `functable`, `funcdomain`, `functodomain` y `funcfromdomain`, **al principio de la lista** (teclea `funct…`, `funcd…`, `functo…`, `funcf…`; también `toDomain` / `fromDomain` / `TableName`). Se generan a partir de los campos del struct y solo para los que aún no tienen la función.

- **Dominio por nombre**: `NoteModel` → `note.Note` (paquete `note`, tipo `Note`). Los campos se pasan en orden al constructor y se leen con getters (`n.Title()`).
- **Constructor real**: si el archivo importa `…/note` y el paquete está en el módulo, se busca en él `Reconstitute`, `Rehydrate`, `Restore`, `Hydrate`, `FromPersistence` o `Load`. Si no se encuentra, queda `Reconstitute` como placeholder editable (Tab).
- **Varios modelos en el archivo**: `functodomain NoteModel`, y `fromDomain` pasa a `fromNoteDomain` para no chocar.
- El import del paquete de dominio lo añade `goimports` al guardar. El formato (alineación de `ID:   n.ID(),`) lo arregla `gofumpt`.

## Completado contextual (`utils/gosmart.lua`)

Lee el árbol de treesitter para saber **dónde estás** y ofrece solo lo que aplica. La ventana de documentación muestra el código que se insertará.

### Al empezar una declaración (columna 0)
Teclea `func`, `type`, `New…` o el nombre de un struct.
Ahí **no** salen palabras sueltas del buffer ni el `func`/`type` genérico del LSP.

**`func`** — variantes de función:

| Opción | Genera |
|---|---|
| `func` | función simple |
| `func error` | devuelve `error` (con `return nil`) |
| `func value` | devuelve un `T` |
| `func pointer` | devuelve un `*T` |
| `func bool` | devuelve `bool` |
| `func result error` | devuelve `(T, error)` |
| `func pointer error` | devuelve `(*T, error)` |
| `func ctx error` | recibe `ctx context.Context`, devuelve `error` |
| `func ctx result error` | recibe `ctx`, devuelve `(T, error)` |
| `func main` / `func init` | las funciones especiales |

**Métodos por struct** (para *cada* struct del archivo, p. ej. `Envelope`):

| Opción | Genera |
|---|---|
| `func (e *Envelope)` | método con receptor puntero |
| `func (e *Envelope) error` | método que devuelve `error` |
| `func (e Envelope)` | método con receptor valor |
| `func (e Envelope) String` | `fmt.Stringer` |
| `functable` | gorm: `func (NoteModel) TableName() string` con el nombre derivado (`NoteModel` → `notes`, `Category` → `categories`). **Sale el primero**: basta teclear `funct…` (o `func ` / `TableName`). Con varios structs: `functable NoteModel`, `functable Category`… **Solo en archivos `*_model.go` o `model.go`**, y no para structs que ya lo tienen. |
| `funcdomain` | `toDomain` + `fromDomain` de una vez (ver abajo). Sale con `func ` o tecleando `funcd…` |
| `functodomain` | `func (m NoteModel) toDomain() *note.Note { return note.Reconstitute(m.ID, m.Title, …) }` |
| `funcfromdomain` | `func fromDomain(n *note.Note) NoteModel { return NoteModel{ID: n.ID(), …} }` |

**Constructor** — `NewEnvelope` aparece para cada struct **sin** `NewX` y ya trae los campos:

```go
func NewEnvelope(kind Kind, id string, sentAt time.Time) *Envelope {
	return &Envelope{
		Kind:   kind,
		ID:     id,
		SentAt: sentAt,
	}
}
```

Los parámetros salen en lowerCamel (`UserID` → `userID`, `ID` → `id`). Los campos embebidos no entran.

**`funcnew`** — constructor que devuelve `(*X, error)`. Es **opcional**: no sale en la lista hasta que tecleas `funcn…` (a nivel de paquete). Tab/Enter lo insertan:

```go
func New(id, title, content string) (*Note, error) {
	|   // ← cursor aquí: validaciones (largos máximos, vacíos…)
	now := time.Now().UTC()
	return &Note{
		id:        id,
		title:     title,
		content:   content,
		createdAt: now,
		updatedAt: now,
	}, nil
}
```

Los `time.Time` cuyo nombre empieza por `created`, `updated` o `modified` **no son parámetros**: salen de un único `now := time.Now().UTC()`. Cualquier otro `time.Time` (`dueDate`) o `*time.Time` sigue siendo parámetro. Sin campos de ese tipo no se genera `now`.

Los parámetros contiguos del mismo tipo se agrupan. Con un solo struct en el archivo se llama `New`; con varios, `NewX` (y salen varias entradas: `funcnew Note`, `funcnew Other`…).

**`type`** — variantes de tipo:

| Opción | Genera |
|---|---|
| `type struct` | struct vacío |
| `type struct constructor` | struct + `NewX` |
| `type generic struct` | `Set[T comparable] struct` |
| `type interface` | interface vacía |
| `type interface method` | interface con un método |
| `type interface ctx result error` | interface con `(ctx, …) (T, error)` |
| `type enum string` | tipo string + constantes |
| `type enum iota` | tipo int + `iota` |
| `type defined` | `type Name string` |
| `type func` | `type Handler func(…) error` |
| `type error` | error propio con `Error()` |
| `type options` | functional options (`WithX`) |

**Coincidencia estricta por prefijo** (no fuzzy): solo sale lo que *empieza* con lo que tecleaste.

| Tecleas | Sale |
|---|---|
| `f`, `fu`, `func`, `func ` | solo las variantes de `func`, los métodos y los `NewX` pendientes |
| `t`, `ty`, `type`, `type ` | solo las variantes de `type` |
| `New`, `NewE`, `Env` | solo el constructor `NewEnvelope` |
| `func Ne` | solo `NewEnvelope` |
| `pac`, `package`, `i`, `v`, `c`… | nada de esto (lo demás lo ponen el LSP y friendly-snippets) |
| `type Foo`, `func Foo` | nada: estás *nombrando* algo |

### Métodos que faltan para cumplir una interfaz (`utils/goimpl.lua`)
Si un struct **se nota** implementando una interfaz y le faltan métodos, el menú ofrece exactamente esos, con la firma de la
interfaz y un cuerpo útil (0 tokens, sin LLM). Dos sitios:

- **Tras escribir el receptor**: `func (s *noteService) ` abre el menú solo (sin teclear nada) con `…all missing (6)` y cada método
  que falta (`Create`, `Get`, ...). Filtra al teclear (`Se` → `SetDone`). El receptor se usa como lo escribiste (`s`).
- **Al empezar la declaración** (`func ` en columna 0): lo mismo para cada struct del archivo, con la cabecera `func (n *noteService)` ya puesta.

Cómo sabe qué interfaz implementa (la primera que encaje): `var _ NoteService = (*noteService)(nil)`; un constructor que la
devuelve (`func NewNoteService(...) NoteService { return &noteService{...} }`); el nombre (`noteService` ~ `NoteService`,
`postgresNoteRepository` ~ `domain.NoteRepository`, también si la interfaz está en otro paquete del módulo); o lo que ya
implementó. Lo ya escrito no se vuelve a ofrecer.

**Cuerpo**: si el struct guarda una dependencia que es una interfaz (`repo domain.NoteRepository`) y esta tiene un método con la
**misma forma** (tipos de parámetros y de retorno; el nombre da igual), el cuerpo la llama: `Get` → `return s.repo.FindByID(ctx, id)`,
`List` → `s.repo.FindAll(ctx, filter)`, `Delete` → `s.repo.Delete(ctx, id)`. Si no hay equivalente (`Create`, `Update`...) queda el
cursor en el cuerpo con un `return nil, nil` (valores cero) que compila. Con `…all missing` cada cuerpo vacío es un tabstop (Tab salta).

Las interfaces de **otro paquete del módulo** se leen del disco (módulo de `go.mod`) y sus tipos se califican (`Note` →
`domain.Note`); los imports que falten los añade `goimports` al guardar. Las de la librería estándar o de dependencias no se leen:
para esas, gopls ya ofrece `<leader>ca` → "Declare missing methods of …" sobre el error del constructor (rellena todo con
`panic("unimplemented")`).

### Después de `type Envelope `
Ofrece `struct`, `interface` y `func(…)`. Si ya escribiste `struct`, no sale nada.

### Dentro de `interface { }`
Firmas de método: `method`, `method error`, `method value`, `method result error`, `method ctx error`, `method ctx result error`, `embed interface`.

### Nombre de struct en posición de valor → literal ya relleno
Teclea el nombre (`x := Env`) y **`Enter` inserta el struct completo**, sin pasos extra:

```go
o := Envelope{
	Kind: ,
	ID: "",
	SentAt: time.Time{},
}
```

`Tab` salta de valor en valor (cada valor trae su cero por defecto seleccionado). Aplica cuando lo que escribes es un **valor**:

| Contexto | Ejemplo |
|---|---|
| lado derecho de `:=` / `=` | `o := Env`, `o = &Env` |
| `return` | `return Env` |
| valor de un campo | `Outer{In: Env` |
| argumento de una llamada | `process(Env`, `process(a, Env` |

En posición de **tipo** no se activa y sigue el completado normal de gopls: `var e Env`, parámetros `func(a Env`, `new(Env`, `[]Env`.
Solo para structs del mismo paquete; el nombre suelto de gopls/buffer se oculta para no duplicar el ítem.

### Dentro de un literal `Envelope{ }`
Para structs del **mismo paquete** (mismo archivo u otro `.go` de la misma carpeta con el mismo `package`).
El menú se abre **solo**, sin teclear nada, en tres momentos: al escribir `{` (queda `Envelope{|}`), al aceptar `Envelope{}` desde el menú de tipos, y al pulsar `Enter` tras `{` o tras un `campo: valor,`:

| Opción | Hace |
|---|---|
| `fill all fields` | inserta todos los campos que faltan, con valor por defecto; `Tab` salta de valor en valor |
| `Kind`, `ID`, `SentAt`… | un campo suelto: `Kind: █,` con el cursor en el valor |

- Los campos que ya pusiste no vuelven a salir; se repite tras cada `campo: valor,`.
- Valores por defecto según el tipo: `string` → `""`, números → `0`, `bool` → `false`, punteros/slices/maps → `nil`, `time.Time{}`, `Inner{}` (struct del archivo).
- Funciona con `Envelope{`, `&Envelope{` y elementos de `[]Envelope{ {…} }`.
- Con `Envelope{|}` en una sola línea, abre las líneas por ti: queda `Envelope{` / campos / `}`.
- Un `package x_test` no ve los structs de `package x` (no compila sin calificar), así que no los ofrece.
- No se activa en literales posicionales (`T{a, b}`) ni dentro del valor de otro campo (p. ej. argumentos de una llamada).
- Structs de **otros paquetes** (`http.Client{`): lo completa gopls como siempre. Para estos sirve `<leader>gs` (`GoFillStruct`).
- Aquí no salen palabras del buffer, y los campos de gopls se ocultan para no duplicar.

### Dentro de una función
Salen los snippets de sentencia (abajo). Los de declaración se ocultan. Dentro de un struct no sale ninguno.

## Declarar errores centinela (`goerrors`)

Teclea solo el **nombre** del error: el resto aparece solo, en gris, y crece con cada letra (`utils/goerrors.lua`).

```go
ErrDescriptionTooLong|  →  ErrDescriptionTooLong = errors.New("description too long")
```

| Dónde | Tecleas | Se escribe |
|---|---|---|
| dentro de `var ( … )` | `ErrNotFound` | `ErrNotFound = errors.New("not found")` |
| tras `var ` | `ErrInvalidID` | `ErrInvalidID = errors.New("invalid id")` |
| nivel de paquete | `ErrEmptyTitle` | `var ErrEmptyTitle = errors.New("empty title")` |

| Tecla | Acción |
|---|---|
| `Tab` | acepta el texto gris (cursor al final de la línea) |
| `Enter` | lo acepta y abre línea nueva (ideal para seguir con el siguiente error del bloque) |
| `Esc` | lo descarta |

- Parte el nombre por mayúsculas y lo pasa a minúsculas (`TitleTooLong` → `title too long`, `HTTPError` → `http error`).
- Acepta también nombres sin exportar (`errNotFound`). Necesita `Err` + mayúscula (`Error…` no dispara).
- Solo sale con el cursor al final de la línea; mientras hay sugerencia no se abre el menú de completado.
- El import de `errors` lo añade goimports al guardar.
- Dentro de funciones no sale (ahí no se declaran centinelas).

## Snippets de sentencias (`nvim/snippets/go.json`)

Nombres completos: se encuentran tecleando **cualquier parte** (`wrap` → `errorsis`…, `ctx` → los de context).

| Snippet | Inserta |
|---|---|
| `iferr` | `if err != nil { return err }` (el `err` queda seleccionado para cambiarlo; solo dentro de funciones) |
| `errorsis` | `if errors.Is(err, ErrX) { … }` |
| `errorsas` | `var t *MyError; if errors.As(err, &t) { … }` |
| `errorsentinel` | `var ErrX = errors.New("…")` (solo a nivel de paquete; el mensaje derivado del nombre: ver arriba) |
| `contexttimeout` | `ctx, cancel := context.WithTimeout(…)` + `defer cancel()` |
| `contextcancel` | `context.WithCancel` + `defer cancel()` |
| `waitgroup` | `sync.WaitGroup` sobre un range |
| `errgroup` | `errgroup.WithContext` + `g.Go` + `g.Wait` |
| `mutex` | `mu.Lock()` + `defer mu.Unlock()` |
| `once` | `once.Do(func() { … })` |
| `selectcontext` | `select` con `ctx.Done()` |
| `forrangeindex` | `for i, v := range items` |
| `forrangeint` | `for i := range n` (Go 1.22+) |
| `testsubtest` | `t.Run("name", func(t *testing.T) { … })` |
| `testtable` | test table-driven con subtests (solo nivel de paquete) |
| `testhelper` | helper con `t.Helper()` (solo nivel de paquete) |
| `httphandlerjson` | handler HTTP que responde JSON (solo nivel de paquete) |
| `jsondecodebody` | decodificar el JSON del body |
| `slog` | `slog.Info/Error/Warn/Debug(…)` |
| `deferfunc` | `defer func() { … }()` |
| `embed` | `//go:embed` (solo nivel de paquete) |

También siguen disponibles los de **friendly-snippets** que no se duplican (`if`, `ife`, `ir`, `for`, `forr`, `switch`, `sel`, `go`, `df`, `fp`, `ff`, `lp`, `make`, `tf`, `tdt`, `hand`…).
Los de declaración de friendly (`func`, `meth`, `tys`, `tyi`, `tyf`, `finit`, `fmain`) están ocultos a nivel de paquete porque `gosmart` los reemplaza con más variantes.

## Dónde vive cada cosa

| Archivo | Rol |
|---|---|
| `lua/languages/go.lua` | declaración: gopls, goimports, gofumpt, golangci-lint, govet |
| `lua/languages/actions/go.lua` | acciones del menú `<leader>g` |
| `lua/plugins/languages/go.lua` | go.nvim (`tag_transform = "snakecase"`, `tag_options = false`) |
| `lua/servers/gopls.lua` | ajustes de gopls |
| `lua/utils/gotags.lua` | fuente blink: tags de struct |
| `lua/utils/gosmart.lua` | fuente blink: func/type/métodos/constructor/interface + filtros |
| `lua/utils/goimpl.lua` | métodos que faltan para cumplir una interfaz (receptor y declaración), cuerpos que llaman a la dependencia |
| `lua/utils/gomodel.lua` | atajos solo de `*_model.go`: `functable`, `funcdomain`, `functodomain`, `funcfromdomain` |
| `lua/utils/goerrors.lua` | texto fantasma de errores centinela (`ErrX` → `ErrX = errors.New("x")`); Tab/Enter se cablean en `blink.lua` |
| `lua/plugins/editing/blink.lua` | registra las fuentes y filtros (buffer, lsp, snippets) |
| `snippets/go.json` | snippets de sentencias |

## Notas

- Si el árbol de treesitter sale roto (llave sin cerrar), el filtro prefiere **mostrar todo** antes que ocultar algo útil.
- Para ajustar o añadir variantes de `func`/`type`/`method`: tablas `FUNCS`, `TYPES` y `METHODS` en `utils/gosmart.lua`.
- Para añadir un snippet de sentencia: `snippets/go.json`, y si solo aplica dentro de funciones, agrega su nombre a `FUNC_ONLY` en `gosmart.lua`.
