# Project-First Plan (with Recipe as the First Specialized Project Type)

## 1) Product direction

Your core workflow is better modeled as **project + master document + conversation**:
- Every project has a persistent **master context** (preferences, constraints, rules).
- Every project has a **master document** (canonical output).
- You can chat with AI about improving the document.
- The master document changes **only** through explicit user-confirmed apply steps.

For now, the first project type is **Recipe** (with strict structure like ingredients + steps).

---

## 2) Goals and non-goals

### Goals (v1)
- Implement the generic project workflow once, then use it for recipes first.
- Keep recipe output in a strict, consistent format.
- Support recipe creation from dish name, free prompt, and pasted transcript/video text.
- Keep inference limited to trusted local Ollama conditions (same Wi-Fi/trusted endpoint rules).
- Preserve offline access to existing projects/documents/chats.
- Make desktop ↔ phone continuity possible with simple sync.

### Non-goals (v1)
- Multi-user collaboration.
- Public sharing/community features.
- Building additional project types immediately (design for them, don’t implement yet).

---

## 3) Target architecture

Use a **local-first, project-oriented architecture**:

1. Local DB (SQLite/Drift) is source of truth on-device.
2. Supabase sync for personal cross-device continuity (chosen default).
3. Ollama network gate controls when inference actions are enabled.
4. Canonical document state is modified only by explicit patch-apply flow.

---

## 4) Generalized domain model

### `project`
Top-level container:
- `id`
- `type` (`recipe` initially)
- `title`
- `status` (`active`, `archived`)
- timestamps

### `project_context`
Persistent context at project level:
- `id`, `project_id`
- structured preferences/constraints JSON
- optional freeform notes
- timestamps

### `project_document`
Canonical master document for the project:
- `id`, `project_id`
- `schema_type` (e.g., `recipe_v1`)
- structured JSON payload
- `version`
- timestamps

### `project_document_revision`
Immutable document snapshots:
- `id`, `document_id`, `revision_number`
- full document payload
- `change_summary`
- timestamp

### `project_chat_thread`
Conversation channel linked to project/document:
- `id`, `project_id`, `document_id`
- `state` (`active`, `cleared`, `archived`)
- timestamps

### `project_chat_message`
Thread messages:
- `id`, `thread_id`, `role`, `content`
- optional metadata JSON (e.g., tool/model)
- timestamp

### `pending_document_patch`
AI-suggested changes waiting for explicit confirmation:
- `id`, `project_id`, `document_id`
- machine patch JSON
- human-readable diff summary
- `status` (`pending`, `applied`, `rejected`)
- timestamps

---

## 5) Recipe specialization (first project type)

Recipe becomes a schema specialization of `project_document` with `schema_type = recipe_v1`.

### `recipe_v1` canonical schema
- `title`
- `description`
- `servings`
- `times`: `prep_min`, `cook_min`, `total_min`
- `ingredients[]`: `{ item, amount, unit, note? }`
- `steps[]`: `{ index, instruction, duration_min? }`
- `tips[]`
- `substitutions[]`
- `source`: `{ type, raw_text? }`

Rule: recipe UI renders from this structured schema only.

---

## 6) LLM contract (general + recipe-specific)

### General contract (all future project types)
- Model returns strict JSON only.
- JSON must include `schema_type`, `document`, and optional `proposed_patch`.
- Local validator enforces schema before save/apply.

### Recipe-specific contract
- If creating/extracting recipe, output `schema_type = recipe_v1`.
- Enforce required blocks: `ingredients[]` and `steps[]`.
- If malformed: retry with repair prompt up to N attempts, then fail gracefully.

This guarantees consistent formatting and future extensibility.

---

## 7) UX workflow (generic first, recipe example)

### A. Create project + initial document
Inputs:
- title seed (dish name)
- free prompt
- transcript/pasted text

Result:
- system generates canonical document draft
- opens split view:
  - top: master document (formatted renderer)
  - bottom: conversation thread

### B. Converse without auto-mutating master document
- Chat explores substitutions/customizations.
- AI may return a `proposed_patch` attached to response.
- Master document remains unchanged until user confirms.

### C. Explicit apply confirmation
- Show pending patch card: "Review changes"
- Show human-readable diff preview
- Require explicit action: `Apply` or `Reject`
- On apply: update document + write revision

### D. Clear chat mode
- "Clear Chat" affects only thread messages.
- Master document + revisions + context remain intact.
- Allows clean cooking/focus mode after document is settled.

---

## 8) Connectivity constraints (local Ollama policy)

Inference/generation is enabled only when:
1. Ollama base URL matches trusted local endpoints/subnets.
2. Device is on trusted Wi-Fi (SSID/BSSID allowlist).
3. Ollama health check passes.

If any check fails:
- disable send/generate/apply-via-AI actions
- keep browsing/edit-history fully available offline

---

## 9) Sync strategy (chosen): Supabase-first

You chose Supabase, so this plan assumes Supabase from day one.

### 9.1 Connection config in a public repo (safe pattern)
Use **only** the following in app config:
- Supabase project URL
- Supabase `anon` key

This is expected and acceptable in a public repository when RLS is correctly enforced.

Never ship in app code:
- service role key
- database password
- any admin secret

Recommended setup:
- Do **not** hardcode Supabase URL or anon key in source files.
- Load all Supabase config from a git-ignored `.env` file.
- Keep service/admin credentials only in local scripts/CI secrets, never in repo.
- Commit an `.env.example` template with placeholder keys only.


### 9.1.1 `.env` policy
- Add `.env` to `.gitignore`.
- Add `.env.example` with non-secret placeholders (e.g., `SUPABASE_URL=`, `SUPABASE_ANON_KEY=`).
- Fail fast at app startup if required env vars are missing.
- Keep separate `.env` files per environment/device as needed.

### 9.2 Auth model (single-user but still secure)
- Use Supabase Auth with one account (your own).
- App signs in once and stores session securely on device.
- Every row is bound to `owner_id = auth.uid()` for access control.

### 9.3 Simple and secure RLS policy model
For each table (`project`, `project_context`, `project_document`, `project_document_revision`, `project_chat_thread`, `project_chat_message`, `pending_document_patch`):
- Enable RLS.
- Policy rule: authenticated user can access only rows where `owner_id = auth.uid()`.

Minimal policy pattern:
- `SELECT USING (owner_id = auth.uid())`
- `INSERT WITH CHECK (owner_id = auth.uid())`
- `UPDATE USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid())`
- `DELETE USING (owner_id = auth.uid())`

This keeps policies simple and robust for a one-user app.

### 9.4 Sync behavior
- Local DB remains source of truth for UI/offline reads.
- Background sync pushes local changes and pulls remote updates.
- Conflict handling:
  - live document head: last-write-wins
  - revisions: append-only (no data loss of history)

### 9.5 Offline guarantees
- App always reads from local DB first.
- No network required to browse projects, documents, revisions, or chats.
- Sync resumes automatically when online/authenticated.

---

## 10) Phased implementation plan

### Phase 1 — General project/document foundation
1. Introduce generalized entities and repository interfaces.
2. Add document validator pipeline (`schema_type` aware).
3. Add revision + pending patch infrastructure.

### Phase 2 — Recipe type implementation
1. Implement `recipe_v1` schema + validator.
2. Add recipe renderer (ingredients/steps/tips).
3. Add create/extract flows (dish name, prompt, transcript).

### Phase 3 — Conversation + explicit apply flow
1. Link chat threads to project/document.
2. Store AI `proposed_patch` as pending.
3. Add review/confirm/reject UI and revision writes.

### Phase 4 — Local network gating + offline behavior
1. Add trusted network/endpoint settings.
2. Gate inference actions by policy checks.
3. Validate offline read behavior for projects and chats.

### Phase 5 — Cross-device sync (Supabase)
1. Add Supabase client, auth session handling, and `.env`-based config loading.
2. Add `owner_id` to synced tables + RLS policies.
3. Implement bootstrap sync, incremental sync, and manual force-sync button.

### Phase 6 — Personal APK release workflow
1. Android signing and personal release config.
2. Simple update/install docs for phone devices.

---

## 11) Backlog (prioritized)

### P0
- General project/document data model + migrations
- Pending patch + explicit confirmation system
- Split document/chat UI
- Recipe `recipe_v1` schema + renderer + validator
- Trusted local-network inference gate

### P1
- Project context editor (preferences/constraints)
- Transcript-to-recipe extraction hardening
- Revision history viewer + rollback

### P2
- Recipe scaling/unit normalization
- Additional project types built on same foundation
- Optional encrypted export/import backups as secondary safety path

---

## 12) Acceptance criteria for first meaningful release

- You can create a Recipe project from name/prompt/transcript.
- Master recipe document is always valid `recipe_v1` and consistently rendered.
- Chat suggestions do not mutate master document automatically.
- Document only changes via explicit apply confirmation.
- Chat can be cleared while keeping document, context, and revisions.
- Inference is disabled outside trusted local conditions.
- Project started on desktop is available on phone after sync.

---

## 13) Immediate next steps

1. Rename implementation framing from recipe-only entities to generalized project/document entities.
2. Define `recipe_v1` JSON schema in code and validators.
3. Implement pending patch review/apply/reject flow before deeper prompt tuning.
4. Add trusted-network policy module and block inference when policy fails.
5. Implement Supabase schema + simple owner-based RLS and wire app config from git-ignored `.env`.
