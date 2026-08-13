# Task plan: BitPrice UI rework

## Goal
Implement the app icon, textual menu-bar price, larger typography, compact selectable rows, and a bottom chart/detail area without changing non-UI behavior or concurrency contracts.

## Current phase
Complete

## Phases

### Phase 1: Inspect requirements and implementation
- [x] Read all requested project files and relevant tests/scripts
- [x] Record current architecture and constraints in findings.md
- **Status:** complete

### Phase 2: Implement presentation changes
- [x] Add reproducible icon generation and bundle integration
- [x] Change MenuBarExtra to a text label sourced from `menuBarTitle`
- [x] Redesign rows, selection, and detail area with larger Dynamic Type styles
- [x] Add or update deliberate presentation tests
- **Status:** complete

### Phase 3: Verify and repair
- [x] Run strict app build and inspect bundle icon/plist/signing/linkage
- [x] Run all tests
- [x] Review diff for scope and hard-constraint compliance
- **Status:** complete

### Phase 4: Record and hand off
- [x] Complete planning records with tradeoffs and GUI limitation
- [x] Write `.codex-implement/_codex_impl_summary_ui1.md`
- **Status:** complete

### Phase 5: Implement quit and add-coin follow-up
- [x] Route quit confirmation through a dedicated inline `PanelRoute` case
- [x] Move the list quit affordance to the far-left header position
- [x] Align and resize search-result and venue-candidate rows
- [x] Compact the confirm-markets content and actions without changing the panel frame
- **Status:** complete

### Phase 6: Verify and record follow-up
- [x] Run strict app build and full tests
- [x] Verify plist, signing, linkage, icon, forbidden presentation APIs, and diff hygiene
- [x] Record layout tradeoffs and no-Aqua limitation
- [x] Write `.codex-implement/_codex_impl_summary_ui2.md`
- **Status:** complete

### Phase 7: Implement chart axes, larger type, and primary-coin guidance
- [x] Add pure axis helpers and cover normal, flat, and single-point ranges
- [x] Draw price/time axes from actual chart points while preserving gap breaks
- [x] Raise Dynamic Type styles and resize the panel/detail layout
- [x] Clarify the existing primary-coin star control and add an inline hint
- **Status:** complete

### Phase 8: Verify and record UI follow-up
- [x] Run strict build, bundle checks, and full tests
- [x] Audit added lines for forbidden presentation/shortcut APIs and scope
- [x] Record tradeoffs, no-Aqua limitations, and implementation summary
- **Status:** complete

## Key questions
1. How are watched assets identified and deleted, so selection can fall back safely?
2. How are chart venue/quote disclosure and stale/failure states currently derived?
3. What icon-generation mechanism is available without third-party assets or a GUI?

## Decisions
| Decision | Rationale |
|---|---|
| Keep UI selection local to the panel view | Selection is presentation state and must remain distinct from persisted primary selection. |
| Preserve inline `PanelRoute` editors | Separate presentations close a `.window` MenuBarExtra panel. |
| Use single-selection `List(selection:)` tagged by item UUID | Makes the row selectable without nesting the star and Alert buttons inside another button. |
| Put reorder and direct delete controls in the selected detail area | Removes row clutter while keeping structural controls explicit and inline. |
| Draw PNGs headlessly with Core Graphics, then package them with `iconutil` | Produces an original, reproducible icon without downloads, GUI tools, or third-party assets. |

## Errors
| Error | Attempts | Resolution |
|---|---:|---|
| `rg` is unavailable on this host | 1 | Use `find`, `grep`, and `sed` as the documented fallback. |
| Icon-generator `swiftc` tried to write its default module cache under `~/.cache` | 1 | Give the generator a private module cache inside its temporary work directory. |
| macOS 15.6 `iconutil -c icns` rejects complete valid-size iconsets, including one it extracted from Apple's Dock icon | 2 | Keep the required pack attempt, then fall back to a deterministic ICNS container; validate by decoding it with `iconutil -c iconset`. |
| A diagnostic command containing `rm -rf build/IconDebug.iconset` was rejected by the execution safety layer | 1 | Used a uniquely named `mktemp` debug directory instead; no project data was removed. |
| A combined patch expected a duplicated chart-call line that was only an output-display artifact | 1 | Re-read the exact source range and applied the source/test edits against the actual text. |
