# Otter Documentation

This is a dependency-free, generated static documentation site. Pages live in
`src/pages.mjs`; the build script gives each page a clean directory URL such as
`/learn/conditions/`.

```powershell
cd otter-docs
npm run dev
```

Then open `http://localhost:4173`. `npm run build` writes the deployable site
to `dist/`. The generated search index is `dist/search-index.json`.

The site intentionally documents only implemented Otter behavior. Additions to
the language should first be frozen in the language contract and decisions,
then documented here in user-facing terms.
