# NestJS Project

## Stack

NestJS with TypeScript. Check `package.json` for the actual NestJS version and key packages (TypeORM, Prisma, class-validator, etc.).

## Architecture

Modular: each domain area gets its own module with a controller, service, DTOs, and entities. The dependency graph flows in one direction: controller depends on service, service depends on repository/external clients. No circular module dependencies.

```
src/
  <feature>/
    dto/
      create-<feature>.dto.ts
      update-<feature>.dto.ts
    entities/
      <feature>.entity.ts
    <feature>.controller.ts
    <feature>.module.ts
    <feature>.service.ts
  common/
    decorators/
    filters/
    guards/
    interceptors/
    pipes/
  app.module.ts
  main.ts
```

## Hard rules

**Controllers**
- Controllers only orchestrate: receive request, call service, return response. Zero business logic.
- Validate all incoming request bodies and params using DTOs decorated with `class-validator`. Never trust raw request data.
- Return response DTOs or plain objects — never return raw entity objects (avoids leaking DB internals).

**Services**
- All business logic lives in services.
- Services receive dependencies via constructor injection only. Never instantiate dependencies manually with `new`.
- Use TypeORM repositories (injected via `@InjectRepository`) for database access. No raw SQL unless there is a documented performance reason, and even then use query builder, not string concatenation.

**Configuration**
- All environment variables are accessed through `ConfigService` from `@nestjs/config`. Never read `process.env` directly in application code.
- Define a validation schema for env vars (Joi or class-validator + `validateSync`) in `app.module.ts`.

**TypeScript**
- No `any`. Use `unknown` and narrow, or define a type.
- Enable `strict: true` in `tsconfig.json`. Keep it on.

**File naming**
- `kebab-case` for all files: `user.service.ts`, `auth.controller.ts`, `create-user.dto.ts`, `user.entity.ts`.
- Module files always named `<feature>.module.ts`.

**Never**
- Business logic in controllers.
- `any` type.
- Raw `process.env` reads in app code.
- Hardcoded config values (ports, database URLs, secret keys).
- Circular module dependencies.

## DTOs

Use `class-validator` decorators for all request validation:

```typescript
import { IsEmail, IsString, MinLength } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  password: string;
}
```

Apply `ValidationPipe` globally in `main.ts` with `whitelist: true` and `forbidNonWhitelisted: true`.

## Tests

**Unit tests** (`*.spec.ts` co-located with source)
- Mock all dependencies with Jest mocks. A unit test for a service should never touch a real database.
- Use `createMock` from `@golevelup/ts-jest` or manual `jest.fn()` mocks.

**E2E tests** (`test/*.e2e-spec.ts`)
- Use a dedicated test database (SQLite in-memory or a Docker-spun PostgreSQL).
- Reset state between tests with transactions or truncation.

```bash
npm run test          # unit tests
npm run test:e2e      # e2e tests
npm run test:cov      # coverage report
```

## Adding a new feature

1. Create the module: `nest g module <feature>`
2. Create the service: `nest g service <feature>`
3. Create the controller: `nest g controller <feature>`
4. Add DTOs in `<feature>/dto/`.
5. Add the entity in `<feature>/entities/`.
6. Import the module in `app.module.ts` (or a parent module).
7. Write unit tests for the service before wiring the controller.

## Commands

```bash
npm run start:dev     # dev server with watch
npm run build         # compile TypeScript
npm run lint          # eslint
npm run test          # jest unit tests
npm run test:e2e      # e2e tests
npx tsc --noEmit      # type-check without building
```
