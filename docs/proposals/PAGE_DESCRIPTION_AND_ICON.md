# A page's description and icon

**Status:** approved by Jeff, 2026-09-30 (option "On the page"). To be given a
D-number in SPEC-DECISIONS.md when the Studio line and the release line merge;
their D-numbers differ today, so none is assigned here.

## Problem

A built website had a title and nothing else in its `<head>`: a search result
showed no summary, a shared link no preview text, and the browser tab the
default icon. Nothing in Otter could say what a page is about.

## Decision

A page takes two more properties, beside `title`:

```otter
app is a page with title "Tea & Cakes", description "Handmade tea and cakes, baked every morning.", icon "assets/images/icon.png"
```

- `description` is one sentence about the page. The web build writes it as
  `<meta name="description">` and, with the title, as `og:title` /
  `og:description` (what a shared link shows).
- `icon` is a path to an image in the project, relative to the page, like an
  image's `source`. The web build writes `<link rel="icon">`. The file reaches
  the build as any other asset: listed in the manifest's `assets` (Studio
  lists it for you before each build, as it does for images).
- Both belong to the page, so each page of a website (see
  MULTI_PAGE_WEB_BUILD.md) has its own.
- Both are optional; a page without them gets no empty tags.
- They apply to a page (`is a page`) on the web. A window, and the desktop
  runtime, ignore them.

The page title is now HTML-escaped in `<title>` and the page header, as every
other text already was (`"Tea & <Cakes>"` showed broken markup before).

## Where

- `src/Otter.Web.psm1`: the page head. Test: `tests/Web.Tests.ps1` 34.
- Otter Studio: Page properties has Description and Icon (the icon offers the
  project's images); the build lists the icon in the manifest's assets
  (`otter-studio/server/manifest-assets.mjs`).

## Not decided here

- `og:image` (a large preview picture for shared links): social sites need
  an absolute URL, which a static build does not know. It needs a site
  address setting first.
- A desktop window's icon.
