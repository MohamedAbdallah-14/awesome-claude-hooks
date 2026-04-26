# Rust Project

## Stack

Rust. Check `Cargo.toml` for the edition (2021 is the current default), MSRV, and key dependencies. Workspace layout (if any) in the root `Cargo.toml`.

## Commands

```bash
cargo check                   # fast type/borrow check without codegen
cargo build                   # full debug build
cargo build --release         # optimized release build
cargo test                    # run all tests (unit + integration)
cargo clippy -- -D warnings   # lint; warnings are errors
cargo fmt                     # format all source files
cargo audit                   # check dependencies for known vulnerabilities
cargo doc --open              # build and open crate docs
```

## Hard rules

**Build order**
- Always run `cargo check` before `cargo build`. It's faster and catches errors without spending time on codegen.
- `cargo clippy -- -D warnings` must pass clean before committing. Warnings are not acceptable at commit time.
- `cargo fmt` must be run before committing. CI will reject unformatted code.

**Testing**
- Unit tests live in the same file as the code they test, in a `#[cfg(test)] mod tests` block.
- Integration tests live in `tests/`. Each file in `tests/` is a separate test binary.
- `cargo test` must pass fully before marking any task done.
- Use `#[should_panic]` and `Result`-returning tests where appropriate — avoid `unwrap()` in test assertions; use `assert!` / `assert_eq!` with descriptive messages.

**Error handling**
- Prefer the `?` operator for propagating errors. Avoid `unwrap()` and `expect()` in library code — they panic on bad input and are never acceptable in a public API.
- In binary (`main.rs`) code, `expect()` is tolerable at startup for unrecoverable config errors, but document the invariant.
- Use `thiserror` for library error types, `anyhow` for application-level error propagation. Don't roll custom error enums without `thiserror`.

**Unsafe code**
- Mark every `unsafe` block with a `// SAFETY:` comment explaining the invariant being upheld.
- Never add `unsafe` without a compelling reason. Prefer safe abstractions. If you think you need `unsafe`, look for a safe crate that solves the problem first.

**Memory and ownership**
- Prefer owned types in public APIs when the lifetime story is complex. `&str` / `&[T]` for read-only parameters; `String` / `Vec<T>` for owned outputs.
- Avoid `Rc<RefCell<T>>` and `Arc<Mutex<T>>` as a first resort for shared state. Consider message-passing (`mpsc`) or restructuring ownership.

**Dependencies**
- Run `cargo audit` before adding any new dependency. Don't add a crate with known advisories.
- Prefer well-maintained crates with a clear ownership story (check crates.io download trends and last publish date).
- Pin exact versions in `Cargo.lock` for binaries; use `^` ranges in `Cargo.toml` for libraries.

**Never**
- Use `#![allow(unused)]` globally — fix or remove unused items.
- Leave commented-out code in commits.
- Add `println!` debugging to production code — use the `log` crate or `tracing`.
