# Laravel Project

## Stack

Laravel. Check `composer.json` for the actual Laravel version and key dependencies. PHP version in `composer.json` `require.php` or `.php-version`.

## Commands

```bash
php artisan serve              # start dev server
php artisan tinker             # Laravel REPL
php artisan make:model         # generate model (add -mfs for migration, factory, seeder)
php artisan migrate            # run pending migrations
php artisan migrate:rollback   # roll back last migration batch
php artisan test               # run test suite via PHPUnit
vendor/bin/phpunit             # run PHPUnit directly
php artisan queue:work         # process queue jobs
php artisan route:list         # list all registered routes
```

## Hard rules

**Commands**
- Always use `php artisan` for Laravel operations, never raw PHP scripts that duplicate Artisan functionality.
- Use `vendor/bin/phpunit` or `php artisan test` for tests — never a globally installed PHPUnit.

**Testing**
- Test framework is PHPUnit with Laravel's testing helpers (`RefreshDatabase`, `Http::fake()`, etc.).
- Feature tests in `tests/Feature/`, unit tests in `tests/Unit/`.
- Use `php artisan test` before marking any task done. All tests must pass.
- Use model factories for test data — never insert raw rows with `DB::table()->insert()` in tests.

**Security**
- Always use `$request->validated()` or `$request->safe()` to access user input. Never use `$request->all()` to pass data into models or queries — it bypasses validation and enables mass assignment.
- Eloquent mass assignment: define `$fillable` explicitly on every model. Never use `$guarded = []` on models that handle user input.
- No raw DB queries with string interpolation. Use parameterized bindings: `DB::select('select * from users where id = ?', [$id])` or the query builder.
- Credentials go in `.env` (gitignored). Access via `config()` or `env()` only — never hardcode values in source files.

**Queue and async work**
- Any operation that takes more than ~200ms (email, external API call, image processing, report generation) belongs in a queued Job, not a synchronous controller action.
- Use Laravel Events and Listeners for decoupled side effects instead of chaining logic in controllers or models.
- Jobs must be idempotent where possible — `ShouldBeUnique` if duplicate execution would cause data problems.

**Eloquent**
- Use relationships (`hasMany`, `belongsTo`, etc.) instead of manual join queries. The ORM relationship methods are the canonical way to traverse the data model.
- Eager-load relationships to avoid N+1 queries: `User::with('posts')->get()`, not `$user->posts` inside a loop.
- Avoid `whereRaw` and `orderByRaw` unless there is no query builder equivalent.

**Migrations**
- Every migration must have a working `down()` method that fully reverses the `up()`. `Schema::drop` in `down()` is fine; an empty `down()` is not.
- Never edit an already-run migration. Create a new one.
- Check existing migrations before writing a new one to understand the current schema.

**Never**
- Call `$model->update($request->all())` — always validate and use `$request->validated()`.
- Use `DB::statement('DROP TABLE ...')` or destructive raw SQL without a migration.
- Disable CSRF middleware on non-API routes.
- Return sensitive data (passwords, tokens, full user records) in API responses without explicit transformation via API Resources.
