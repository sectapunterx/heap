// The GitHub repository the site belongs to, and so its Pages path: a project
// site lives at https://<owner>.github.io/<name>/. On GitHub Actions it comes
// from GITHUB_REPOSITORY, so renaming the repository moves the site and every
// link with it on the next build; locally it falls back to the current name.
const fullName = process.env.GITHUB_REPOSITORY || 'sectapunterx/heap';
export const REPO = fullName;
export const REPO_NAME = fullName.split('/')[1];
export const BASE = `/${REPO_NAME}`;
