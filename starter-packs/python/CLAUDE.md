# Python Project

## Stack

Python 3.10+. Check the project root for `pyproject.toml` or `requirements.txt` to determine the framework in use (FastAPI, Django, plain scripts, etc.) and the pinned versions.

## Style

- Follow PEP 8. Line length: 88 (Black default). Enforced by the linter hook.
- Type hints on every function signature — parameters and return types. Use `from __future__ import annotations` at the top of each file for forward references.
- Use `pathlib.Path` for all file system operations. Never `os.path`.
- String formatting: f-strings only. No `%` formatting, no `.format()`.

## Hard rules

**Errors**
- Handle every exception explicitly. Bare `except:` is forbidden. Catch the narrowest exception type that makes sense.
- Never silence exceptions with an empty `except` block. Log and re-raise, or handle and document why.

**Security**
- Never use exec() or eval() with any data that originates from user input, network, or files.
- Never build SQL queries with string concatenation or f-strings. Use parameterized queries or an ORM.
- Never use wildcard imports (`from module import *`).
- Secrets and config come from environment variables only. Read them via `python-dotenv` loaded in a single `config.py` or `settings.py`. Never read `os.environ` directly in application code.

**Async**
- Use `async/await` consistently. Never call a synchronous blocking function (file I/O, `requests`, `time.sleep`) inside an `async def` function. Use `asyncio.to_thread` or the async equivalent.
- Do not mix `asyncio.run()` inside functions that are themselves async.

**Imports**
- Standard library then third-party then local. One blank line between groups.
- No circular imports. If you need to break a cycle, move the shared code to a new module.

**Never**
- Wildcard imports.
- Hardcoded credentials, URLs, or file paths that belong in config.
- Mutable default arguments (`def foo(items=[]):`). Use `None` and assign inside the function body.
- `print()` as a logging mechanism in application code. Use the `logging` module.

## Dependencies

- Add to `pyproject.toml` (`[project.dependencies]`) or `requirements.txt`.
- Pin major versions at minimum (e.g., `fastapi>=0.110,<1.0`). Pin exact versions in `requirements.lock` or via `pip-compile`.
- Dev-only tools (pytest, black, ruff, mypy) go in `[project.optional-dependencies]` or `requirements-dev.txt`.

## Tests

- Framework: pytest.
- Shared fixtures in `conftest.py` at the appropriate directory level.
- No test should touch the real database, real filesystem, or real network. Use mocks, `tmp_path`, or a test-specific SQLite/in-memory database.
- Name test files `test_<module>.py`, test functions `test_<what_it_does>`.
- Run: `pytest` or `pytest -x` to stop on first failure.

## Project layout (adjust to match actual structure)

```
src/
  <package_name>/
    __init__.py
    config.py        # env var loading
    main.py          # entry point / app factory
    models/
    services/
    routers/         # FastAPI: API routes; Django: views/urls
tests/
  conftest.py
  test_<module>.py
pyproject.toml
```

## Commands

```bash
pip install -e ".[dev]"          # install with dev extras
python -m pytest                 # run tests
python -m ruff check .           # lint (fast, replaces flake8)
python -m mypy src/              # type-check
python -m black .                # format
uvicorn src.main:app --reload    # FastAPI dev server (adjust path)
```
