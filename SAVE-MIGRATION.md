# Save handling and recovery

Save handling is part of **Install.cmd**. No separate converter, Python installation or manual folder renaming is required.

## Before installing

Close Scarlett and preserve the complete original game and `savedata` folder. Start a new game with the English patch: Japanese scene saves are unsupported.

Japanese shared progress, such as Cyclopedia registrations, can be converted when no unsupported scene saves are present. If a profile cannot be converted, keep the whole folder intact and ask for help rather than deleting saves to force installation.

## If the installer asks about an existing profile

Choose the version that created the scene saves. For an original Japanese profile containing shared progress only, choose **Original Japanese game (shared progress only)**. The glossary-origin checkbox identifies registrations carried over from the Japanese game.

The currently installed game alone cannot prove a copied save's origin. Cancel if unsure. Do not select a different version to bypass a conversion refusal.

## What the installer preserves

- The complete pre-install save profile, retained as `savedata-before` under that installation's backup directory.
- Read history and unrelated save-folder files.
- Save data outside the verified execution-position and glossary-index fields.

The full profile is validated before converted files replace `savedata`. Unsupported signatures, unknown layouts and unmapped positions stop the conversion. A small `scarlett-save-version.json` marker identifies the resulting format.

## Restore

1. Close Scarlett.
2. Run **Restore.cmd** and choose the same game folder.
3. If several installation receipts are offered, choose the installation you intend to undo.

Restore returns the exact pre-install game files and save profile. Newer progress is retained under the selected backup as `savedata-after-patch`. It is not converted for the restored Japanese game; retain it for reinstallation or individual recovery.

Backups and receipts live under `Scarlett-English-Patch/backups` in the game folder. Keep them. Restore does not merge profiles or silently discard newer saves.

## Interrupted installation or restoration

Close the game and rerun **Restore.cmd** with the same receipt. Recovery validates known files before restoring them; unexpected external changes are refused. Preserve the backup directory and error message if recovery needs individual assistance.

## Compatibility

The conversion tables apply to this v1.0 build. Future patches require their own checked mappings. Bounded opening-save tests do not establish compatibility with every possible scene save. See [VALIDATION.md](VALIDATION.md).
