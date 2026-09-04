# Code review — 2026-09-04

Full review of the repository (`src/`, `tests/`, `main.adb`, the Liquid
template), performed with Claude Code's `/code-review` (`--target .
--level high`) plus a manual read-through, cross-checking the
parsing logic against the `convert-startup-to-vectors.mjs` reference
it mirrors (including a direct `node -e` check of the regex this
found a divergence from).

## Bug found and fixed

**`Is_Comment_Only_Line`'s `/* ... */` check used overlapping index
windows on short strings.**

- File: `src/vector_table_parser.adb`
- Function: `Is_Comment_Only_Line`, meant to mirror the JS regex
  `/^(?:\/\*.*\*\/|@.*|\/\/.*)$/`

Before the fix:

```ada
if Trimmed_Line'Length >= 2
  and then Trimmed_Line (F .. F + 1) = "/*"
  and then Trimmed_Line (L - 1 .. L) = "*/"
then
   return True;
end if;
```

For a 3-character line, `F + 1 = L - 1`, so the same character was
checked as both the second character of `"/*"` and the first
character of `"*/"`. The 3-character string `"/*/"` satisfied both
conditions off that shared middle `*`, even though it is not a
self-contained comment — the JS regex it's supposed to mirror
requires at least 4 characters (`"/**/"` is the minimum match) and
returns `false` for `"/*/"` (confirmed with `node -e`).

**Impact**: a `startup_<device>.s` file with a stray/typo'd 3-char
`/*/` line between `.word` entries would be silently tolerated by the
Ada parser and scanning would continue past it, while the JS tool
this project mirrors would instead treat that line as ending the
vector-table scan — a real, silent divergence for that input shape.
Low-probability trigger in practice, but a genuine byte-for-byte
mirroring bug.

**Fix**: require `Trimmed_Line'Length >= 4` instead of `>= 2`.

**Regression test**: `tests/parser_selftest.adb`, `Test_Short_Slash_Star_Line`
(Case 5) — feeds `Vector_Table_Parser.Parse` a table with a `"/*/"`
line between two `.word` entries and asserts the table now correctly
ends at 1 entry.

Status: fix and test applied to the working tree; **not yet verified
by a real build/run**, since no Ada toolchain (`gprbuild`/`gnatmake`/
`alr`) was available in the environment this review was done in. Run
`gprbuild -P vectors_gen.gpr && ./obj/parser_selftest` (or the
project's usual build step) to confirm before relying on this beyond
the review itself.

## Smaller improvement opportunities (not bugs, not applied)

1. **Duplicated "read a whole file" logic** between `main.adb`'s
   `Read_Whole_File` and `vector_table_parser.adb`'s `Read_Lines` —
   both hand-loop over `Ada.Text_IO.Get_Line`/`End_Of_File` for the
   same purpose, returning different shapes (`String` vs.
   `Line_Vectors.Vector`). Worth a shared helper if a third reader
   ever appears; not worth changing on its own.

2. **AST nodes (`Expression_Access`/`Node_Access`) are never
   deallocated.** Fine for this program's actual lifetime
   (parse → render once → exit); would start to matter only if this
   Liquid-subset machinery were reused as a long-lived library
   rendering many templates in one process.

3. **Input-side file reading uses `Ada.Text_IO`, not `Stream_IO`.**
   The project already documents carefully why `Text_IO` mangles
   trailing-newline handling on the *output* side; the same
   `Get_Line`-based reading is fine on input today (well-formed
   line-oriented text), but the asymmetry is worth knowing about
   explicitly rather than "fixing" inconsistently later.

4. **Magic vector-table indices in `main.adb`** (`Table (5).Symbol =
   "0"` for ARMv6-M detection, `Table (8).Symbol /= "0"` for ARMv8-M)
   are already well-commented but could be named constants (e.g.
   `MPU_Fault_Slot`, `Secure_Fault_Slot`) so a future reader doesn't
   have to re-derive the indexing from the comment.

## What's solid

- `Render_Context` as a fixed record (not a string-keyed map) is a
  good structural fix for the exact bug class that bit the JS
  version twice (see `docs/CHAT.md`).
- `Ada.Streams.Stream_IO` for output correctly avoids GNAT
  `Text_IO`'s trailing-newline gotcha — verified against the golden
  fixture byte-for-byte per `docs/CHAT.md`.
- Lexer whitespace-trim handling (`{%-`/`-%}`), the parser's
  recursive-descent grammar, and the evaluator's path/filter
  semantics (`minus`, `slice`, including liquidjs's own clamping edge
  cases) all check out against both their own tests and the JS
  reference.
- Test coverage is genuinely end-to-end: `tests/renderer_selftest.adb`
  diffs a full real template render against a real golden
  `vectors-stm32h533xx.c`, not just isolated unit assertions.
