# Agent instructions

## Repository roles

The current Antigravity project contains three repositories:

1. **VeneraX**
   - PRIMARY writable development repository.
   - This is the only repository that may be modified by default.

2. **venera-configs**
   - READ-ONLY reference/config repository by default.
   - It may be inspected for Venera comic-source definitions and runtime behavior.
   - Do not modify it unless explicitly authorized for a task that requires coordinated
     source-config changes.

3. **extensions-source**
   - STRICTLY READ-ONLY reference repository by default.
   - It is used to study Mihon/Keiyoushi implementations, patterns, networking,
     authentication, source behavior, and reader/source concepts.
   - Do not modify it unless explicitly told otherwise.

Mihon and Komikku may be used as architectural and UX references.
Do not blindly copy or mechanically translate their Kotlin/Android implementations into VeneraX.
Prefer adapting concepts to VeneraX's existing Flutter/Dart, QuickJS, source runtime, networking,
and reader architecture.

## Git branch policy

- `master` is the stable upstream-compatible branch.
- Do not implement features directly on `master`.
- Do not commit to `master` unless explicitly instructed.
- `develop` is the long-lived integration branch for our custom VeneraX development.
- New implementation work should normally use focused branches such as:
  - `feature/...`
  - `fix/...`
  - `refactor/...`
- Feature branches should normally start from `develop`.

Never automatically:
- push
- force-push
- merge
- rebase
- reset
- delete branches
- rewrite history
- clean untracked files

These actions require explicit user approval.

Never use destructive commands such as:
- `git reset --hard`
- `git clean -fd`
- `git push --force`
- `git push --force-with-lease`

unless explicitly requested and reviewed for that specific operation.

## Before modifying code

Before implementation:

1. Confirm the intended writable repository.
2. Run/read `git status --short`.
3. Confirm the current branch.
4. Inspect the relevant existing architecture before changing it.
5. Reuse existing abstractions where possible.
6. For non-trivial work, provide an implementation plan before editing.
7. Keep the requested task narrowly scoped.

Do not perform unrelated cleanup or refactoring while implementing a feature.

## Architecture preservation

Respect VeneraX's existing architecture.

Important systems include:

- Flutter/Dart application architecture (`lib/foundation/`)
- QuickJS comic-source runtime (`lib/foundation/comic_source/`, `lib/foundation/js_engine.dart`)
- Venera JS source/config system
- Dio/network layer
- Cookie management
- WebView / Cloudflare handling
- SQLite/data persistence
- Reader architecture
- Image translation/OCR pipeline

Do not bypass an existing abstraction just because a local workaround is easier.

If an architectural extension is required, explain:
- why the existing abstraction is insufficient
- what compatibility impact the extension has
- which modules/repositories are affected

before implementation.

## High-risk files

Treat large or central files as high regression-risk, including:

- `lib/pages/reader/images.dart`
- `lib/pages/reader/scaffold.dart`
- `lib/pages/reader/reader.dart`
- `lib/foundation/comic_source/parser.dart`
- `lib/foundation/comic_source/comic_source.dart`
- `lib/foundation/js_engine.dart`
- `lib/foundation/image_translation/pre_translation_tasks.dart`
- large comic-source UI modules such as `comic_source_page.dart`

Do not perform broad refactors of these files as part of an unrelated feature.

Prefer the smallest coherent change.

## Current development priorities

Use this priority order unless explicitly changed:

### Priority 1 — Source compatibility architecture

Improve VeneraX's ability to support useful source patterns found in
Mihon / Keiyoushi / Komikku ecosystems.

Study reference implementations where useful, including:
- HTML sources
- JSON/API sources
- Webtoon-style sources
- Kakao/API-style sources
- cookies/session handling
- authentication
- WebView/interceptor patterns
- headers/Referer/User-Agent
- rate limiting
- Cloudflare/anti-bot handling
- image extraction/reconstruction

Do not directly port Kotlin source code.
Map capabilities into VeneraX's JS-source and application architecture.

### Priority 2 — Actual comic sources

After the compatibility design is stable, prioritize practical source work,
including candidates such as:

- Webtoon
- Kakao
- 愛看漫
- 拷貝漫畫
- other useful Korean/Chinese comic sources

Prefer solving reusable architectural gaps instead of adding source-specific hacks
when possible.

### Priority 3 — Reader UX improvements

Reader improvements are intentionally deferred until the source system is stable.

Future Reader UX references may include Komikku and Mihon.

Desired future behaviors include:
- configurable page whitespace/margins
- tablet/desktop maximum page width
- adaptive large-screen layout
- smooth pinch-to-zoom
- double-tap to restore/default zoom
- paged-reader scaling
- Webtoon/continuous-reader adaptive width
- consistent behavior across Android, tablet, and Windows

Komikku's interaction model may be studied as a UX reference.

Because Komikku is Android-native while VeneraX is Flutter and cross-platform,
do not assume its implementation can be directly reused.

If reproducing the full gesture behavior creates excessive cross-platform complexity,
prefer a simpler EZVenera-style page-margin/layout implementation first,
and defer advanced zoom behavior.

### Priority 4 — Later enhancements

Only after core source support is stable:
- related-link / source lookup features
- reader convenience features
- translation provider improvements
- Gemini/native LLM improvements
- additional synchronization enhancements

## Validation after modifications

After any implementation:

1. Review `git diff`.
2. Verify only intended files changed.
3. Run the narrowest relevant static analysis/tests.
4. Do not automatically perform expensive full builds unless necessary.
5. Report warnings/errors honestly.
6. Run `git status --short`.
7. Do not commit or push unless explicitly authorized.

## Reference repository policy

Reading from:
- `venera-configs`
- `extensions-source`

is encouraged when it materially helps implementation.

Writing to them is prohibited by default.

If a task appears to require changes outside VeneraX:
STOP and explain why before modifying anything.

## Security and secrets

Never:
- commit API keys
- commit passwords/tokens
- expose cookies/session credentials in logs or artifacts
- place secrets in source control

Use existing secure/configuration mechanisms.

## Multi-agent working-tree ownership

- Only one modifying AI agent may own a working tree at a time.
- Codex, Antigravity, Copilot, DeepSeek-backed agents, or other agents must not simultaneously modify the same working tree.
- Parallel implementation requires separate Git worktrees / branches.
- Read-only agents may inspect concurrently only if they do not mutate repository or runtime state.

## Agent startup protocol

Before modifying code, every incoming agent must:

1. Read `AGENTS.md`.
2. Read `.ai/handoff/current.md` if it exists.
3. Run/read `git status --short`.
4. Confirm current branch.
5. Confirm current HEAD.
6. Inspect relevant `git diff`.
7. Verify working-tree state agrees with handoff state.

If the working tree contains unexplained changes:
STOP and report the discrepancy.

## Handoff protocol

A handoff is required whenever:
- an agent pauses unfinished work,
- quota is nearly exhausted or exhausted,
- the user switches AI provider/account,
- work is intentionally transferred to another agent,
- a blocker prevents completion.

The outgoing agent must record enough state in `.ai/handoff/current.md` (using `.ai/handoff/TEMPLATE.md`) for another agent to continue without chat history.

## Verification gate

Before declaring implementation complete or ready for handoff:

1. Inspect `git diff`.
2. Run `git diff --check`.
3. Run `flutter analyze`.
4. Run the narrowest relevant tests.
5. For comic-source/runtime changes, run the appropriate runtime validation when feasible.
6. Run `git status --short`.

Passing verification must NOT be interpreted as permission to commit or push.

## Generated files policy

- Do not manually edit generated/build artifacts unless they are explicitly the authoritative source for the task.
- Prefer modifying source inputs and regenerating through the repository's intended mechanism.
- Do not introduce generated/temp artifacts into Git accidentally.

## Secrets and local agent configuration

Never store:
- API keys
- DeepSeek credentials
- Codex authentication
- Google authentication
- GitHub tokens
- cookies/session credentials

in `AGENTS.md`, handoff documents, tracked logs, tracked source files, or Git history.

Provider/authentication configuration must remain machine-local unless a future task explicitly creates a safe, secret-free project configuration.

## Final rule

When safety, repository ownership, scope, or intended architecture is ambiguous:

STOP,
report the ambiguity,
and ask for explicit approval before making the questionable change.
