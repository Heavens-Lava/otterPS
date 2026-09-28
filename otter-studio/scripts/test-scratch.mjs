// test-scratch.mjs - temporary projects for Studio tests that drive the server.
//
// Tests such as first-milestone, project-manifest and workspace-solution call
// the real server API (create-project, project-manifest, create-solution, file
// save). Those endpoints write to disk and stamp fresh timestamps (`created`,
// `trustedAt`). They used to target tracked fixtures under projects/, so every
// run left modified tracked files -- which a clean-checkout certification
// rejects.
//
// Instead, each test run now gets its own scratch folder:
//
//     projects/.studio-test-tmp/<label>-<pid>/
//
// How it works:
//   - It lives inside the repository because the server only serves paths
//     under the repository root (it rejects anything outside as Forbidden).
//   - `projects/.studio-test-tmp/` is in .gitignore, so even a run that is
//     killed before cleanup cannot dirty `git status`.
//   - The folder is deleted when the process exits. Node runs 'exit'
//     listeners on a normal finish, on process.exit(n), and after an uncaught
//     exception or a failed top-level await, so failing tests clean up too.
//     'exit' listeners must be synchronous, hence fs.rmSync.
//   - Ctrl+C (SIGINT) and SIGTERM skip 'exit' by default, so they are turned
//     into process.exit(), which runs it.
import fs from 'node:fs';
import path from 'node:path';

export const SCRATCH_ROOT = 'projects/.studio-test-tmp';

/**
 * Create an empty scratch folder for this test run and delete it on exit.
 * @param {string} repoRoot absolute repository root (the server's root)
 * @param {string} label short name of the test, used in the folder name
 * @returns {{ rel: string, abs: string }} rel is the repo-relative path with
 *   forward slashes, ready to send to the server API
 */
export function createScratchFolder(repoRoot, label) {
  const rel = `${SCRATCH_ROOT}/${label}-${process.pid}`;
  const abs = path.join(repoRoot, ...rel.split('/'));
  // A leftover from an earlier, killed run with the same pid: start empty.
  fs.rmSync(abs, { recursive: true, force: true });
  fs.mkdirSync(abs, { recursive: true });
  // A server this test starts keeps its Local History here, not in the
  // user's ~/.otter-studio/history (server/local-history.mjs).
  process.env.OTTER_STUDIO_HISTORY_DIR ??= path.join(abs, '.local-history');

  const cleanup = () => {
    try {
      fs.rmSync(abs, { recursive: true, force: true });
      // Remove the shared parent too once no other run is using it.
      const parent = path.dirname(abs);
      if (fs.existsSync(parent) && fs.readdirSync(parent).length === 0) fs.rmdirSync(parent);
    } catch (err) {
      // Never mask the test's own result; the folder is git-ignored anyway.
      console.error(`test-scratch: could not remove ${rel}: ${err.message}`);
    }
  };
  process.on('exit', cleanup);
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => process.exit(130));
  }
  return { rel, abs };
}
