# Rustcore — working notes

This file is already in your context — it auto-loads every session. **Never `Read` it,
`FOREVER-MAP.md`, or `handoff.md`. Re-reading them is the fault.** Everything here
exists so that nothing below has to be rediscovered by reading source.

## Working rule: edit first, never survey

Do not build a complete mental picture before touching anything. The four biggest
files are 1400–1600 lines each; reading them whole exhausts the context window, the
session compacts, and the next session re-reads the same files. That loop has burned
several conversations and produced zero edits.

Locate → read a narrow window → edit. Nothing else.

## How to find code without reading files

`map/` holds one small index per Lua file — every top-level function with its line
number, never more than ~60 lines. `FOREVER-MAP.md` is just the table of contents,
and carries the authoritative per-file line counts.

    grep -rn "GetSelfFoundIconTexture" map/              # -> Rustcore.lua:325
    sed -n '325,340p' dist/forever/Rustcore/Rustcore.lua # -> read just that

Regenerate after structural edits: `bash tools/forever-map.sh`

## Reading constraints (harness mangling)

Wide output gets compressed on the way back and comes back **mangled** — Lua keywords
silently dropped, unrelated lines spliced. Never edit from mangled text. **Window
width is what matters, not which tool you use.**

- Clean: `grep -n`, `sed -n 'A,Bp'` up to ~15 lines, `Read` with `offset`/`limit` ~20 lines.
- Mangled: full-file `cat`, `sed -n` over ~60 lines, recursive `find`.
- Listings: narrow globs (`ls -1 dir/*.lua`), never recursive `find`.
- **Bash heredocs eat backslashes.** Anything containing a regex or a WoW texture path
  (`Interface\AddOns\...`) goes through a Python file written to the scratchpad, or the
  Write/Edit tools. A mangled regex once faked a Lua syntax-depth error.
- Generate artifacts with `> file` and print only `wc -l`, so generated content never
  enters context.

## Hard rules against context exhaustion

Breaking any of these has compacted the conversation mid-task more than once — most
recently whole-file reads of `Verification/Time.lua` and `Verification/UI.lua`.

- **Never call `Read` on a `.lua` file without `offset` and `limit` ≤ 20.** No exceptions,
  including "small" files and everything under `Verification/`.
- **Grep always with line numbers**: `output_mode: "content"` + `-n`, or `grep -n` in Bash.
  `files_with_matches` returns no line numbers and forces a follow-up read.
- The only loop is: grep → read ≤20-line window → edit. Never "look around" a file.
- Never re-read a window you already read. Note the line numbers you found in the
  task notes above so the next session skips the search too.
- The Edit tool needs a prior `Read` of the file — satisfy it with a narrow
  offset/limit read of exactly the lines being changed, never a full read.
- If a fix spans many sites, grep for all of them first, then do narrow read+edit
  pairs one at a time.

## Repo layout

| Path | What it is |
| --- | --- |
| `dist/forever/Rustcore/` | **Current work scope.** Build for the Forever client. |
| `release/Rustcore/` | Live release tree — root Lua/UI edits must be mirrored here. |
| `release/Rustcore1.43/`, `release/Rustcore1.47/` | Frozen snapshots. Never edit. |
| `mirrored/Rustcore/` | Mirror target. |

Branch: `1.4-Forever` (main is `main`).

`dist/forever` and the root tree have diverged; reconcile before mirroring anything
between them. The Forever tasks below are scoped to `dist/forever/Rustcore/` only.

Per-file line counts live in `FOREVER-MAP.md`. The four 1400+ files are the reason sessions blow up. Splitting them is cheap in WoW
Lua — a new file just needs a line in `Rustcore.toc` — but do it only when asked.

## The five Forever tasks — do ONE per conversation

1. ~~**Self-found buff icon renders as a green square on Forever.**~~ **DONE** —
   fixed in `Rustcore.lua:325`. Existence probe + texture-validity check, falls back
   to the bundled TGA. Do not revisit.
2. ~~**Self-found buff:** anchor LEFT of the leftmost buff.~~ **DONE.** Do not revisit.
3. ~~**Target verification buff:** anchor RIGHT of the rightmost buff.~~ **DONE.**
   `IsVerifiedTarget()` was preserved whole, including its `dragonTargetFrame`
   early-return that task 5 depends on. Do not revisit.
4. **Horizontal stats panel:** a long item name stays on the stat row and gets pushed
   far right. `RustcoreStats.lua`. **IN PROGRESS — no edit made yet.** Findings:
   `ComputeLayout` starts at 602; 603 reads the `statsHorizontalLayout` setting.
   The `if horizontal / elseif long` at 617–621 sets `cols` ONLY. The `if long then`
   at 628 is at function-body top level and runs in BOTH modes, so the long strip
   *is* reserved — there is no missing branch. In horizontal mode `cols = count`,
   so `gridW` is very wide and `stripW = math.max(gridW, longW)` always collapses
   to `gridW`, leaving the two-column long frame inside a much wider strip. That is
   the likely cause. Next step: `sed -n '633,646p'` to see where the long cell's
   x/y is written into `layout.cells`, then edit. Apply site is ~810 in
   `RefreshLayout`. Lines 602–632 were read clean and need no re-reading.
5. **Dragon overlay:** the `dist/forever` art is already pure dragon artwork. Do NOT
   hide or remove the portrait frame — overlay the dragon on top of it the way the game
   does for elite/rare. `RustcoreDragon.lua`.

### Tasks 2 and 3 — what was done

`RustcoreSelfFoundBuff.lua` went 657 → 283 lines. It used to blank the native
`BuffFrame` and redraw every buff from scratch, with a parallel implementation for
`TargetFrame` and an `OnUpdate` loop re-applying the suppression every frame — the
source of the combat-lockdown symptoms. Both halves now leave Blizzard's frames
completely alone and anchor a single icon beside the existing auras.

Deleted along the way: `PositionSlot`, `ComputePerRow`, `AddWeaponEnchantSlot`,
`AddAura`, `SetNativeTargetAurasHidden`, the button pools, `MANUAL_OFFSET_X`, and both
`HideNativeBuffFrame()` / `ShowNativeBuffFrame()`.

**Neither task has been verified in-client.** Worth an eyes-on check: buffs with the
bar wrapped to a second row, and a verified target with both buffs and debuffs up.
