# Clipboard History V1 Spec

## Overview

Add a clipboard history feature to Steward that records plain-text clipboard entries up to 4 KB, stores them in a JSONL file, and exposes them in a dedicated History window opened from the menu bar.

This feature should fit the current app architecture, where `AppDelegate` owns app lifecycle, menu construction, and standalone windows.

## Goals

- Record all plain-text clipboard entries whose size is `<= 4096` bytes.
- Store the captured text and the capture timestamp for every accepted record.
- Persist records across app launches using JSONL.
- Add a dedicated History window reachable from a new menu item placed above `Preferences...`.
- Let the user delete individual records from the History UI.
- Let the user clear all records from the History UI.
- Keep clipboard history overhead low enough that it does not noticeably affect app launch, hotkey responsiveness, or system idle efficiency.

## Non-Goals

- No search, filtering, favorites, or tagging in v1.
- No clipboard sync across devices.
- No export or import flow.
- No support for images, rich text, files, or other non-string pasteboard types.
- No deduplication. Repeated copies are stored as separate records.
- No retention limits or automatic pruning in v1.

## Definitions

- `clipboard record`: one accepted plain-text clipboard capture.
- `size`: the UTF-8 byte count of `text`.
- `history file`: the JSONL file that persists all clipboard records.
- `internal clipboard write`: a clipboard mutation caused by Steward itself while performing grammar replacement or OCR output handling.

## User Stories

- As a user, when I copy short text in any app, I want Steward to keep a history of it.
- As a user, I want to open a History window from the menu bar and review my past clipboard records.
- As a user, I want to remove an individual record if I no longer want to keep it.
- As a user, I want to clear my entire clipboard history in one action.
- As a user, I want my history to still be there after restarting the app.

## Functional Requirements

### Capture Rules

- Monitor `NSPasteboard.general` continuously after app launch.
- Detect clipboard changes using `changeCount` polling.
- Read only plain text using the general pasteboard string representation.
- Accept a clipboard item only when all of the following are true:
  - it can be read as plain text,
  - it is not empty,
  - `text.utf8.count <= 4096`.
- Store the text exactly as captured, including whitespace and line breaks.
- Store duplicate copies as separate records.

### Required Stored Fields

Each clipboard record must contain:

- `id`: a stable unique identifier used by the UI and delete actions.
- `capturedAt`: the date and time when the record was accepted.
- `text`: the captured clipboard string.
- `size`: the UTF-8 byte count of `text`.

### Persistence Rules

- Persist records in a JSONL file in the app's Application Support directory.
- Use one JSON object per line.
- Append newly captured records to the end of the file.
- Load existing records on app launch.
- Keep records in memory for fast UI rendering.

### Deletion Rules

- Support deleting a single record from the History UI.
- Support clearing all records from the History UI.
- Persist delete-one and clear-all actions to disk immediately.
- Delete-one and clear-all must update the visible list without requiring app restart.

### Menu And Navigation Rules

- Add a new menu item named `History` above `Preferences...` in the status item menu.
- Selecting `History` opens a dedicated standalone window.
- If the History window is already open, selecting `History` brings the existing window to the front.

## Architecture

## High-Level Design

The implementation should be split into three responsibilities.

### 1. Clipboard Monitor

Responsible for:

- polling pasteboard `changeCount`,
- reading plain-text clipboard content,
- applying acceptance filters,
- forwarding accepted records to persistence,
- suppressing Steward's own temporary clipboard writes.

### 2. Clipboard Store

Responsible for:

- resolving the Application Support file location,
- loading and decoding JSONL records at startup,
- appending new records,
- rewriting the file after delete-one,
- clearing the file for clear-all,
- exposing the current in-memory records to the UI layer.

Performance requirements for this layer:

- keep an authoritative in-memory snapshot so the UI never re-reads the file just to render,
- perform file I/O off the main thread,
- serialize all write operations through one store-owned queue to avoid contention and file corruption,
- avoid full-file rewrites on append.

### 3. History Window / UI Layer

Responsible for:

- rendering the current records,
- opening and reusing the History window,
- handling delete-one and clear-all actions,
- showing empty and selected states cleanly.

## Suggested File Organization

The current app is concentrated in `Sources/Steward/Steward.swift`, but this feature should be split into new focused files under `Sources/Steward`.

Recommended structure:

- `ClipboardHistoryRecord.swift`
- `ClipboardHistoryStore.swift`
- `ClipboardMonitor.swift`
- `ClipboardHistoryView.swift`

`AppDelegate` should remain the owner that wires everything together.

## Data Model Spec

### Clipboard Record Shape

Each JSONL line should represent one record with this logical schema:

- `id`: string UUID
- `capturedAt`: ISO 8601 timestamp string
- `text`: string
- `size`: integer

Example logical record:

- `id`: `550e8400-e29b-41d4-a716-446655440000`
- `capturedAt`: `2026-03-07T14:22:31Z`
- `text`: `Hello world`
- `size`: `11`

### Field Semantics

- `id` exists only to make list diffing, selection, and deletion stable.
- `capturedAt` must represent the time the record was accepted by Steward, not file write time.
- `text` is the exact clipboard content preserved without trimming.
- `size` is always computed from `text.utf8.count` and not from character count.

## JSONL Storage Spec

### File Location

Store the history file under the app's Application Support folder.

Recommended location:

- `~/Library/Application Support/Steward/clipboard-history.jsonl`

### File Format

- UTF-8 encoded text file.
- One valid JSON object per line.
- No surrounding array.
- New records appended as new lines.

### Read Path

On launch:

- ensure the parent directory exists,
- if the file does not exist, initialize with empty history,
- if the file exists, read line by line,
- decode each line independently,
- skip malformed lines instead of failing the whole load,
- build the in-memory record list.
- perform this load asynchronously so app launch, menu creation, and hotkey setup are not blocked by history hydration.

### Write Path

For new records:

- append one new JSON line to the file,
- update in-memory state immediately.
- use compact single-line JSON encoding with no extra whitespace.
- the append path must not re-read or rewrite the existing file.

For delete-one and clear-all:

- rewrite the file from the authoritative in-memory list,
- use atomic replacement so partial writes do not corrupt the file.
- run delete-one rewrites off the main thread so row deletion feels immediate in the UI.
- clear-all should prefer deleting or truncating the history file directly rather than performing a line-by-line rewrite.

### In-Memory Ordering

- Disk order should remain oldest to newest because JSONL appends naturally that way.
- UI order should be newest first.

## Pasteboard Monitoring Spec

### Startup Behavior

- Start monitoring after application launch completes.
- Initialize the last-seen pasteboard `changeCount` before polling begins so existing clipboard content is not retroactively recorded at startup.
- Do not block menu bar startup on history load completion.

### Polling Strategy

- Use a lightweight repeating timer on the main run loop or another safe app-owned loop.
- Poll frequently enough to feel responsive but not aggressively. Recommended target: every `750 ms`.
- Set timer tolerance so the system can coalesce wakeups and reduce idle power usage.
- On each tick, do no work beyond a `changeCount` check unless the pasteboard actually changed.

### Change Detection Flow

When polling detects a changed `changeCount`:

1. Read current plain-text clipboard content.
2. If no string is available, ignore the change.
3. Compute `size` as `text.utf8.count`.
4. If `size > 4096`, ignore the change.
5. If text is empty, ignore the change.
6. If the change is currently suppressed as an internal Steward mutation, ignore it.
7. Otherwise create a new record, append it, and publish it to the UI.

Hot-path efficiency requirements:

- read the pasteboard string at most once per detected change,
- compute `size` once and reuse it for filtering and persistence,
- avoid any synchronous history file write on the same execution path that updates UI state,
- avoid expensive formatting work such as per-record date formatting during capture.

## Internal Clipboard Suppression Spec

This is required because Steward already uses the clipboard internally.

### Current Internal Clipboard Flows

- Selected text capture in `getSelectedText()` temporarily writes the current selection to the clipboard.
- Grammar replacement in `replaceSelectedText(with:)` temporarily writes replacement text and later restores previous clipboard content.
- OCR flow in `copyTextToClipboard(_:)` writes extracted text to the clipboard.

### V1 Suppression Policy

Recommended policy for v1:

- suppress temporary clipboard writes used only to make grammar correction work,
- record the final OCR copy result because it is user-visible clipboard content.

That means:

- do not store the temporary selection copy generated by `Command+C` simulation,
- do not store the clipboard restoration step after grammar replacement,
- do not store transient internal replacement text if it is only part of the grammar-paste workflow,
- do store OCR text copied as the final result of screen text capture.

### Suppression Mechanism Requirements

- The monitor must support a way to ignore one or more upcoming `changeCount` increments caused by Steward.
- Suppression should be explicit at the call sites that write to the clipboard.
- Suppression should be narrow and temporary, not a broad paused-monitor state that risks missing legitimate user copies.

## History Window Spec

### Window Behavior

- Open as a separate titled window, not inside Preferences.
- Reuse a single window instance while the app is running.
- If the window is already visible, bring it to front instead of creating a duplicate.
- Closing the window should only release that window reference and should not affect the app lifecycle.
- Create the History window lazily on demand instead of at app launch.

### Layout Recommendation

Use a two-pane utility layout.

#### Top Bar

- title: `Clipboard History`
- secondary text showing record count
- `Clear All` button aligned to the trailing edge

#### Left Pane: Record List

Each row should contain:

- a preview of the clipboard text,
- a smaller timestamp,
- a delete button on the row.

Row behavior:

- single selection,
- newest items shown first,
- preview truncated to keep the list scannable,
- rows remain compact enough to browse many items quickly.

Rendering efficiency requirements:

- the list should be backed by the in-memory records snapshot and never trigger a file read during normal scrolling,
- row previews should be lightweight and bounded in length,
- timestamp formatting should use shared formatter instances rather than creating new formatters per row render,
- only the selected item should render full text in the detail pane.

#### Right Pane: Record Detail

Show the currently selected record with:

- full text in a scrollable read-only text area,
- full timestamp,
- optional `size` display as supporting metadata.

If nothing is selected:

- show an empty-detail placeholder.

### Empty State

When there are no records:

- show a centered empty state message,
- hide or disable detail behavior that depends on a selection,
- still show `Clear All` as disabled.

## UI Interaction Rules

### Initial Selection

- When the window opens and records exist, auto-select the newest record.

### After New Record Capture

- Insert the new record at the top of the visible list.
- If the user has not manually selected another record yet, select the new top item.
- Avoid jarring selection changes if the user is reading an older item.

### After Delete-One

- Remove the row immediately.
- If the deleted row was selected, select a nearby neighbor if one exists.
- If no records remain, switch to the empty state.

### After Clear-All

- Present a confirmation prompt before destructive deletion.
- After confirmation, clear the list and show the empty state.

## Error Handling Spec

### Load Errors

- If the file cannot be opened, the app should continue running with empty in-memory history.
- If one JSONL line is malformed, skip it and continue loading the rest.
- Loading failure should not block core app features like grammar correction or OCR.

### Write Errors

- If append fails, the app should not crash.
- If delete-one or clear-all rewrite fails, the UI should remain internally consistent and surface a lightweight user-visible error if practical.
- File I/O failures should not break the menu bar app lifecycle.

## Performance Spec

- The feature must remain responsive with low daily volume and multi-year retention.
- History loading should be fast enough for normal menu-bar app launch expectations.
- Appending one record must be lightweight.
- Full rewrite on delete-one is acceptable in v1 because projected file size is modest.
- The feature must not add noticeable latency to grammar correction, OCR, or menu interactions.
- The feature must avoid synchronous disk I/O on the main thread during normal capture flow.
- The feature must not re-parse the JSONL file when opening the History window if the in-memory snapshot is already loaded.
- The feature should minimize idle CPU and wakeups by using a tolerant polling timer and a cheap no-change fast path.
- The feature should use compact JSON encoding and incremental append writes to keep disk overhead low.

### Performance Implementation Notes

- Maintain one store-owned in-memory array as the source of truth for the UI.
- Use a dedicated serial queue for file appends, rewrites, and clear operations.
- Publish store changes back to the UI on the main thread.
- Prefer deleting the history file for clear-all over rewriting an empty JSONL payload.
- Keep any derived presentation data, such as preview text, transient and in-memory only if needed.
- Do not pre-create or pre-render the History window until the user asks for it.

## Privacy And Product Considerations

- Clipboard history is sensitive and may capture passwords, tokens, or private text.
- V1 should avoid silently capturing Steward's temporary internal clipboard traffic.
- The app should preserve exact text content, so the History UI must be treated as sensitive content display.
- If the feature is enabled by default, product copy should make the behavior obvious. If a toggle is later added, the current storage design remains compatible.

## Acceptance Criteria

The feature is complete when all of the following are true:

- Copying a plain-text string under `4 KB` in another app creates a new persisted record.
- Copying plain text over `4 KB` does not create a record.
- Each stored record contains `id`, `capturedAt`, `text`, and `size`.
- Records persist after quitting and relaunching Steward.
- A `History` menu item appears above `Preferences...` and opens a standalone History window.
- The History window shows all records newest first.
- Each visible row has a delete action.
- The window has a `Clear All` action.
- Delete-one removes the record from both UI and disk.
- Clear-all removes all records from both UI and disk.
- Grammar correction clipboard internals do not spam the history.
- OCR output is captured in history under the recommended v1 policy.

## Manual Test Scenarios

### Basic Capture

- Copy `hello` from another app.
- Open History.
- Verify one new record appears with correct text, timestamp, and `size`.

### Oversized Capture

- Copy a plain-text string larger than `4096` UTF-8 bytes.
- Verify no new record appears.

### Duplicate Capture

- Copy the same short string multiple times.
- Verify each copy creates a separate record.

### Persistence

- Copy several valid strings.
- Quit and relaunch Steward.
- Verify the records still appear.

### Delete-One

- Delete one record from the History list.
- Verify it disappears immediately.
- Relaunch Steward and verify it stays deleted.

### Clear-All

- Clear all records using the top-level action.
- Verify the list becomes empty.
- Relaunch Steward and verify it remains empty.

### Grammar Flow Noise Suppression

- Trigger grammar correction on selected text.
- Verify temporary internal clipboard writes do not create extra history entries.

### OCR Flow

- Trigger screen OCR and let Steward copy the extracted text.
- Verify the final copied OCR text appears as a history record.

## Future Extensions

The chosen JSONL design should keep room for later additions without blocking v1.

Possible future enhancements:

- search and text filtering,
- retention limits,
- favorites or pinning,
- copy-back action from History,
- source labels for rows,
- migration from JSONL to SQLite,
- settings toggle to enable or disable history.
