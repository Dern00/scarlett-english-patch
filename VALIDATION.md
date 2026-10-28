# Migration validation

Tests were performed in an isolated game copy with frozen release archives. No original installation, workbook, or real user savedata was changed.

- Created an ordinary opening save using the released RC5 scripts. Converted two console frame positions, loaded it under RC7, advanced to the next passage, opened the backlog, and returned normally.
- Created an ordinary opening save using released RC6 scripts and loaded it under RC7. Its active positions did not need changing.
- Built a clearly identified Japanese-layout glossary fixture containing Beretta M92F, Orange marking, and Kadena Air Base across three profiles. Converted it and verified the correct English headings and the complete Kadena card in RC7.
- Tested every one of the 104 glossary keys across the 3 × 14 × 108 matrix while preserving all bytes outside the matrix.
- Confirmed a malformed file and an unknown script position stop conversion, and no output folder is created when validation fails.
- Confirmed source folders and read-history bytes remain unchanged, existing destinations are refused, and converting a migrated scene as RC7 produces identical bytes.
- Restored the isolated game's prior savedata and closed the game after testing.

These are bounded compatibility checks, not an exhaustive playthrough or a promise that every old save will load. Unknown releases and ambiguous states remain excluded. The converter does not repair unrelated pre-existing corruption.

All review and tests in this migration pass were performed by the current agent; no independent reviewer is claimed.
