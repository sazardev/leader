<!-- name: Go CLI subcommand -->
<!-- desc: a subcommand with its flags, the code it runs and a test of its output -->
<!-- for: go+!server -->
<!-- input: name | Name of the command (e.g. export, sync) -->
<!-- input: does | What it does, its arguments and flags (one sentence) -->

# Recipe: the `{{name_kebab}}` command

{{does}}

## Make

- The subcommand `{{name_kebab}}` with the CLI library the project uses (cobra, urfave/cli, kong, or the standard `flag` package with the existing dispatch), registered next to the other commands.
- The work in a function that takes its inputs and an `io.Writer`, returns an error, and knows nothing about flags (testable without the CLI).
- Help text: one line of usage, a short description and an example.

## Rules

- Output on stdout, diagnostics on stderr; machine output (`--json`) when the other commands have it.
- Exit codes: 0 ok, 1 failure, 2 wrong usage; errors say what to do next.
- No global state: configuration comes in through the function's arguments.

## Tests

- The function with a buffer as writer: the main case, an invalid argument, and an error from what it calls.
- The command parses its flags and arguments (one test through the CLI library).
