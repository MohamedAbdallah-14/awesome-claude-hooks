# Go Project

## Stack

Go. Check `go.mod` for the module path and Go version. Check `go.sum` for dependency status.

## Hard rules

**Error handling**
- Handle every error. Never assign an error return to `_` unless you have an explicit written justification in a comment on the same line.
- Do not wrap errors with `fmt.Sprintf("error: %v", err)`. Use `fmt.Errorf("context: %w", err)` to preserve the error chain.
- Error messages are lowercase and do not end with punctuation. They will be wrapped by callers.

**Context**
- Every function that does I/O, makes a network call, queries a database, or runs for an indeterminate time must accept `context.Context` as its first parameter.
- Never store a `context.Context` in a struct. Pass it through the call chain.
- Respect cancellation: check `ctx.Err()` or select on `ctx.Done()` in loops and long-running goroutines.

**Cleanup**
- Use `defer` for all cleanup: closing files, releasing locks, cancelling contexts, closing database rows.
- Check the error from `defer`ed calls where it matters (e.g., `defer f.Close()` in a write path — capture and log or return the error).

**Interfaces**
- Define interfaces at the consumption site, not the implementation site. The package that uses an interface defines it; the package that implements it knows nothing about the interface.
- Keep interfaces small. One or two methods is ideal. If you need more, question whether it's really one interface.

**Packages**
- Short, lowercase names, no underscores, no abbreviations that require domain knowledge to decode.
- No stutter: a type `User` in package `user` should not be `user.UserService` — it should be `user.Service`.
- Avoid `util`, `common`, `helpers` packages. Name packages by what they provide, not what they are.

**State**
- No global mutable state. Package-level `var` is acceptable for read-only data (e.g., compiled regexps, static maps). Mutable shared state belongs in a struct with explicit ownership.
- Avoid `init()` except for registration patterns (e.g., registering a database driver, registering a codec). Document why if you use it.

**Concurrency**
- Run tests with `-race`. Fix all data races before merging.
- Prefer channels over shared memory with mutexes when the communication model fits. Use mutexes when you need to protect a data structure, not to send data.
- Document goroutine ownership: who starts it, who stops it, how it signals completion.

**Never**
- Naked `return` in functions with more than 3 lines (named returns make code hard to follow at length).
- `panic` in library code. Only in `main` or initialization paths where recovery is impossible.
- `//nolint` or `//noinspection` without a comment explaining why.

## Tests

- Test files: `<file>_test.go` in the same package.
- Test function naming: `TestFunctionName`, `TestFunctionName_scenarioDescription`.
- Use `t.Helper()` in helper functions so failure lines point to the caller.
- Prefer table-driven tests for functions with multiple input/output cases:

```go
func TestAdd(t *testing.T) {
    cases := []struct {
        name string
        a, b int
        want int
    }{
        {"positive", 1, 2, 3},
        {"zero", 0, 0, 0},
        {"negative", -1, -2, -3},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            got := Add(tc.a, tc.b)
            if got != tc.want {
                t.Errorf("Add(%d, %d) = %d, want %d", tc.a, tc.b, got, tc.want)
            }
        })
    }
}
```

- Use `testify/assert` or plain `t.Errorf` — no external test framework dependency beyond `testify` unless the project already uses one.
- No test should depend on another test's state. Each test is independent.

## Commands

```bash
go build ./...              # build all packages
go test ./...               # run all tests
go test -race ./...         # run tests with race detector (required before merging)
go vet ./...                # static analysis
go fmt ./...                # format (or use gofmt/goimports)
golangci-lint run           # lint (if configured)
go mod tidy                 # clean up go.mod and go.sum
```
