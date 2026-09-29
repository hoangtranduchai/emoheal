# Git Workflow & Best Practices

EmoHeal utilizes **GitHub Flow**, a lightweight, branch-based workflow suitable for modern continuous integration environments.

**Repository:** `hoangtranduchai/emoheal`

## General Rules

*   **NEVER commit directly to the `main` branch.**
*   All work must be done in feature or bugfix branches.
*   All code merged into `main` must pass review via a Pull Request (PR).

## Branch Naming Convention

Branches should be prefixed with their type, followed by a brief, kebab-case description.

*   `feature/[description]` — For new features (e.g., `feature/magic-link-login`)
*   `bug/[description]` — For bug fixes (e.g., `bug/radio-player-crash`)
*   `hotfix/[description]` — For urgent fixes to production (e.g., `hotfix/auth-token-expired`)

## The Workflow Steps

1.  **Sync `main`:** `git checkout main` -> `git pull`
2.  **Create Branch:** `git checkout -b feature/your-feature-name`
3.  **Develop:** Make your changes locally.
4.  **Commit:** Commit frequently with descriptive messages.
5.  **Push:** Push your branch to the remote repository. (`git push -u origin feature/your-feature-name`)
6.  **Pull Request:** Open a PR on GitHub targeting the `main` branch.
7.  **Review:** Address any feedback from reviewers.
8.  **Merge:** Once approved, merge the PR (squash merge is preferred to keep the history clean).
9.  **Cleanup:** Delete the branch locally and remotely.

## Commit Message Format

We follow a structured commit message format, including both English and Vietnamese for clarity among all team members.

**Format:** `type(scope): description [EN] / Mô tả [VI]`

**Valid Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.

**Examples:**
*   `feat(auth): add Magic Link login / Thêm đăng nhập Magic Link`
*   `fix(radio): fix audio player crash / Sửa lỗi player audio crash`
*   `docs(readme): update setup instructions / Cập nhật hướng dẫn cài đặt`
*   `refactor(home): migrate to Riverpod / Chuyển sang dùng Riverpod`

## Git Safety Rules

*   **Undoing Pushed Commits:** Use `git revert <commit_hash>`. This is safe because it creates a *new* commit that undoes the changes, preserving history.
*   **Undoing Local (Unpushed) Commits:** You may use `git reset`. Use with caution.
*   **Work In Progress:** Use `git stash` to temporarily shelf changes if you need to switch branches quickly without committing incomplete work.
*   **Always Pull:** Always run `git pull` before branching off to ensure you have the latest code.

## `.gitignore` Configuration

Ensure sensitive or generated files are never committed. The `.gitignore` must include:

```
# Environment variables
.env
.env.*

# Build artifacts
build/
/build/
*.app/

# Python / FastAPI
__pycache__/
*.pyc
venv/

# IDE settings
.idea/
.vscode/

# Flutter/Dart
.dart_tool/
.packages
pubspec.lock # (Optional depending on team policy, usually committed for apps, ignored for packages)
```
