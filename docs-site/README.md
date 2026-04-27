# docs-site

Static catalog browser for `awesome-claude-hooks`. Deployed to GitHub Pages
at https://mohamedabdallah-14.github.io/awesome-claude-hooks/.

## What it is

Three plain files plus the registry:

- `index.html` — page shell, header, sidebar, results region.
- `styles.css` — single stylesheet, dark by default with a light media
  query, no external assets, system fonts only.
- `app.js` — vanilla JS. Fetches `registry.json` (a copy of the repo's
  `hooks.registry.json`), renders filter controls from the data, and
  rebuilds the card grid on every input change.
- `registry.json` — generated. Not committed. Created by the Pages workflow
  or by `make pages-serve`.

No build step. No npm. No frameworks. No CDN. No tracking.

## Develop locally

From the repo root:

```sh
make pages-serve
```

That:

1. Copies `hooks.registry.json` to `docs-site/registry.json`.
2. Starts `python3 -m http.server 8000` inside `docs-site/`.

Open <http://localhost:8000>.

If you'd rather run it by hand:

```sh
cp hooks.registry.json docs-site/registry.json
cd docs-site && python3 -m http.server 8000
```

The page does an `XHR` for `./registry.json`, so you must serve over HTTP —
opening `index.html` via `file://` will fail to fetch.

## Deploy

`.github/workflows/pages.yml` runs after the main `CI` workflow on `main`
succeeds. It:

1. Checks out the SHA that triggered CI.
2. Skips deploy unless that commit touched `docs-site/**` or
   `hooks.registry.json` (avoids a deploy on every doc-only change).
3. Copies `hooks.registry.json` to `_site/registry.json`.
4. Uploads `_site/` and deploys via the official `deploy-pages` action.

Manual rebuilds: trigger the **Pages** workflow from the Actions tab.

## Adding a hook

Hooks come from `hooks.registry.json`, which is generated from the script
headers under `hooks/` by `scripts/build-registry.py`. The site will pick
up the new entry automatically on the next deploy.

If your hook has a long-form doc at `docs/hooks/<id>.md`, also add `<id>`
to the `HERO_DOCS` map at the top of `app.js` so the "view hero doc" link
shows up. (We hard-code that list rather than `HEAD`-ing every URL — fewer
moving parts, and it's easy to keep in sync since hero docs are rare.)

## Constraints

- Total HTML + CSS + JS is kept under ~1500 lines combined. Keep it tight.
- No external font, no analytics, no service worker.
- Must remain accessible: keyboard nav, ARIA labels on filters, semantic
  HTML, focus-visible outlines.
- Must work down to 360px wide.
