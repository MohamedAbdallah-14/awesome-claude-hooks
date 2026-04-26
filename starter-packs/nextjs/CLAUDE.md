# Next.js Project

## Stack

Next.js 14+ with App Router, TypeScript, Tailwind CSS, Jest + React Testing Library.

## Architecture

- `app/` — App Router pages and layouts. All components here are Server Components by default.
- `components/` — Shared UI components. Check here before writing a new one.
- `lib/` — Utilities, helpers, API clients. `camelCase` filenames.
- `types/` — Shared TypeScript types and interfaces. Co-locate types with the file that owns them when they are not shared.

## Hard rules

**Server vs Client Components**
- Server Components are the default. Only add `'use client'` when you need browser APIs, event handlers, or React hooks (useState, useEffect, etc.).
- Never fetch data inside a Client Component if the same data can be fetched in a parent Server Component and passed as props.
- Avoid `'use client'` at layout or page level — push it down to the smallest component that actually needs it.

**TypeScript**
- No `any`. Use `unknown` and narrow, or define a proper type.
- Co-locate types with the module that owns them. Export from `types/` only when consumed by three or more modules.
- Use Zod for all external data validation (API responses, form input, env vars).

**Styling**
- Tailwind only. No inline `style` props except for dynamic values that Tailwind cannot express (e.g., CSS custom properties).
- No CSS modules, no styled-components.

**Components**
- PascalCase filenames for components: `UserCard.tsx`, `NavMenu.tsx`.
- Extract any JSX repeated more than once into its own component.
- Named exports for components (not default exports), so refactoring tools can track them.

**Never**
- `console.log` in production code. Use a logger or remove before committing.
- Class components.
- `export default` for components (use named exports).
- Mutation of props or external state outside of a server action or API route.

## Data fetching

- Fetch in Server Components using async/await directly.
- Use `cache()` from React for request deduplication where needed.
- Mutations go in Server Actions (`'use server'`). Validate input with Zod before touching the database.

## Environment variables

- Prefix client-safe vars with `NEXT_PUBLIC_`.
- Validate all env vars at startup using a Zod schema in `lib/env.ts`. Never read `process.env` directly outside that file.

## Testing

- Framework: Jest + React Testing Library.
- Test files: co-located as `ComponentName.test.tsx` or in `__tests__/`.
- Render components with `render()`, assert with `screen` queries. Never test implementation details.
- Mock `next/navigation` and `next/image` in tests that import them.
- Run: `npm test` or `npx jest --watch`.

## Adding a feature

1. Check `components/` for an existing component that does something similar.
2. If server-only data fetching is needed, do it in the page/layout Server Component.
3. Add Zod schemas for any new external data shapes.
4. Write at least one test for non-trivial logic.

## Commands

```bash
npm run dev          # start dev server
npm run build        # production build (catches type errors)
npm run lint         # eslint
npm test             # jest
npx tsc --noEmit     # type-check without building
```
