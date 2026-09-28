# Otter 1.0 project manifest (`otter.json`)

A project is a folder with a manifest file. This document describes the
manifest as Otter 1.0 reads it. `otter new <type> <name>` writes one for you.

## Which file is read

- **`otter.json` is the Otter 1.0 manifest.** Use it for every new project.
- **`project.json` is a legacy fallback.** Otter reads it only when the folder
  has no `otter.json`. When both files exist, `otter.json` wins and
  `project.json` is ignored without a warning.
- Naming a manifest file directly (`otter run project.json`,
  `otter build otter.json`) uses that file.
- The file name is matched exactly on Linux and macOS: `Otter.json` is not
  found there.

## Example

```json
{
  "name": "my-app",
  "version": "0.1.0",
  "archetype": "console",
  "target": "console",
  "entryPoint": "main.ot",
  "assets": [],
  "build": { "outputDir": "dist", "clean": true },
  "scripts": {
    "start": "otter run .",
    "test": "otter test .",
    "check": "otter check ."
  }
}
```

## Fields

"Every project command" means `otter check`, `otter run`, `otter <folder>`,
`otter web`, `otter desktop`, `otter serve`, `otter build` and
`otter publish`. `otter test` only uses the manifest to find the project
folder; it runs the tests under `tests/` without validating the manifest.

| Field | Type | Default | Required | Used by | Rules |
|---|---|---|---|---|---|
| `entryPoint` | text: a path relative to the project folder | none | **Yes**, for every project command | every project command | Must name an existing file inside the project folder. `run` and `check` also require a `.ot` file. |
| `name` | text | the project folder's name | For `otter publish` only | `build` (metadata), `publish` (zip name, metadata) | Characters that cannot appear in a file name are replaced with `-` in the zip name. |
| `version` | text | `"0.1.0"` | For `otter publish` only | `build` (metadata), `publish` (zip name, metadata) | To publish, it must be a plain version string: letters, digits, `.`, `+` and `-`, starting with a letter or digit, and without `..` (for example `1.2.0` or `1.0.0-rc.1`). Write it as text in quotes: a JSON number such as `1.10` would be read as `1.1`. |
| `target` | text | `archetype`, otherwise `"console"` | No | `build`, `publish` (which pipeline to use) | One of `console`, `desktop`, `web`, `game`, `automation`, `server`; not case-sensitive. `otter build` does not support `server`. |
| `archetype` | text | same as `target` | No | fallback for `target`; copied into metadata | Written by `otter new`. |
| `assets` | list of text paths | empty list | No | `build` (copied to `dist/` at the same relative path), `publish` | Each asset must be an existing file inside the project folder: absolute paths, paths that leave the project with `..`, folders and wildcards are refused. |
| `build.outputDir` | text | `"dist"` | No | `build`, `publish` | Must stay inside the project folder and must not be the project folder itself. If the folder already exists and was not created by `otter build` (it has no `otter.build.json`), Otter refuses to delete it. |
| `build.clean` | `true` or `false` | `true` | No | `build` | `true` empties the output folder before building. With `false`, files from earlier builds stay and are included when you publish. |
| `publish.outputDir` | text | `"publish"` | No | `publish` | Must stay inside the project folder. `otter publish . --output <dir>` (or `-Output <dir>`) overrides it. |
| `scripts` | object of text commands | none | No | nothing | Written by `otter new` as a reminder of the usual commands; Otter never runs them. |
| `main` | text | none | No | every project command | Legacy: read only from `project.json`, and only when `entryPoint` is missing. Ignored in `otter.json`. |
| `$schema` | text | none | No | nothing | Written by `otter new`; not read. |
| `build.sourceMaps`, `build.minify` | `true` or `false` | `true`, `false` | No | nothing | Read but not used in 1.0. |

Any other field is ignored. Otter 1.0 does not reject a field of the wrong
type in every case (for example, a number where text is expected), so use the
types listed above.

## Staying inside the project

`entryPoint` and every entry in `assets` must stay inside the project folder.
Otter enforces this for `check`, `run`, `build` and `publish`, including when
a path goes through a symbolic link (or, on Windows, a junction) that points
outside the project. `build.outputDir` and `publish.outputDir` must also stay
inside the project folder.

## What `otter check .` validates

`otter check .` reads the manifest, checks `entryPoint`, and parses the entry
point and every file it imports with `use`. It does not check other `.ot`
files in the project (such as tests), and it does not check `assets`,
`publish.outputDir`, or the `name` and `version` that `otter publish` needs.

## Web projects

For a web project, keep `entryPoint` at the project root. A stylesheet named
after the entry point, beside it (`main.css` for `main.ot`), is included in
the page by `otter web`, `otter build` and `otter publish`; it is the only
stylesheet rule in Otter 1.0. Run a web or game project with `otter web .`.

## Exit codes

A manifest problem stops `check`, `run`, `web`, `desktop` and `serve` with
exit code 2, and `build` and `publish` with exit code 1.
