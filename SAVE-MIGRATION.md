# Save migration to RC7

The converter creates a **new folder of converted copies**. It never edits the source folder. The original folder is the rollback copy.

## Supported scope

| Source | Scope |
| --- | --- |
| RC5 | Verified source-position mappings to RC7; ordinary opening save loaded and advanced in game |
| RC6 | Verified mappings to RC7; ordinary opening save loaded in game |
| RC7 | Structural validation and unchanged copies where the glossary already uses the English layout |
| Original Japanese shared progress | Glossary entry indexes converted by original stable keys; settings and other progress preserved |

RC1–RC4 scene saves, Japanese scene saves, development/test builds, unknown positions, and mixed or corrupted glossary histories are not supported. A successful opening test is not proof that every scene save is compatible. Unknown positions cause an error rather than a guessed conversion.

All released RC1–RC7 dictionaries use the same layout. Choose `japanese` only when the saved glossary registrations were created using the original Japanese dictionary. A folder carried forward from an older build may retain that older layout even after starting a new game.

## Use

1. Close Scarlett completely. Keep the existing `savedata` folder.
2. Put `scarlett_save_migration.py` and `save-migration-maps.json.gz` together. Install Python 3.10 or newer if needed.
3. Run a conversion, replacing the example paths with your own:

```powershell
py -3 scarlett_save_migration.py "D:\Games\Scarlett\savedata" "D:\Games\Scarlett\savedata-rc7" --from-release rc5 --dictionary english-rc1-rc7
```

For RC6 saves, use `--from-release rc6`. For Japanese shared progress with no scene saves, use `--from-release japanese --dictionary japanese`.

4. If it succeeds, rename the original folder to `savedata-before-rc7`, then rename the converted folder to `savedata`. Do this while the game remains closed.
5. Open RC7, load a known save, advance, check the backlog and dictionary, and confirm your unlocks. Retain the original folder until you are satisfied.

To roll back, close the game, move the converted folder aside, and restore the original folder's name. Restore the matching earlier patch as well.

If the folder contains scene saves created under different releases, do not label the entire folder as one version. Convert copies grouped by their known source release and retain the original folder. If a source version is uncertain, leave that save untouched for individual assessment.

## What changes

- Proven script execution/return positions in scene saves.
- Nonzero glossary indexes in the known-entry matrix, across all three profiles.

Other save bytes, screenshots, settings, unlocks, and read-history files are preserved. The output includes a receipt of input/output hashes and changed fields, without absolute source paths. Malformed files, unexpected layouts, existing output folders, and repeated conversion of a receipt-bearing output folder are rejected.

This utility is separate from the installer. It does not automatically overwrite or activate converted files. Future patch releases require their own checked mapping tables; the current tables target RC7 only.
