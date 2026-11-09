# v1.0 validation

Testing used isolated game copies and disposable installer fixtures. The original installation and translation workbook were preserved.

## Automated checks

- Workbook source/ID integrity and integrated-ledger verification across 83,250 rows.
- A targeted glossary consistency audit, with contextual variants checked before deciding whether a correction was needed.
- Chapter-menu instruction/control-flow preservation, click-rectangle geometry and normal/selected/pressed bitmap states.
- Twenty installer/save transaction checks, including injected failures, interrupted installation and Restore, repeated runs, invalid-data refusal and preservation of newer progress.
- Byte-for-byte agreement between the Windows save converter and a separate reference implementation, covering all 104 glossary keys across the 3 × 14 × 108 registration array.
- Actual extracted-package installation, repeated installation, direct update and layered rollback on full-size disposable copies.
- Package membership, file checksums, standardized ZIP metadata and scans for local identifying data, including decrypted scripts inside the patch archive.

## In-game checks

- Fully unlocked and partially unlocked chapter menus, chapter/Intermission navigation and the NEW marker.
- Two ordinary opening scene saves converted to v1.0, dialogue advancement and backlog return.
- Creating and reloading a new save after conversion.
- Japanese shared-progress conversion showing Beretta M92F, Orange marking and Kadena Air Base.
- Kadena's complete nine-line entry and switching to Beretta without leftover text.

Earlier bounded rendering checks covered the game's dialogue styles, name panels, large/small emphasis, backlog and representative long passages.

## Coverage boundaries

These are bounded tests, not an exhaustive playthrough or a guarantee for every existing save. Unknown execution positions are refused. The PowerShell-hosted save-version selector could not be visually inspected by desktop automation; its conversion/transaction functions were checked with explicit source selections. Hover-only chapter-menu states were not exercised natively. Broader speech verification remains deferred.
