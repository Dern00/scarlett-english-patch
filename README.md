# Scarlett English Patch

English translation patch for the original Windows PC release of **Scarlett**, with both original game updates installed.

This repository is private while testing continues. The current playable package is **RC7**. The save converter is a separate, newly tested utility; the RC7 ZIP itself has not been changed.

## Installation

Use the packaged release ZIP, extract it outside the game folder, and run `Install.cmd`. Follow its folder prompt. Close the game first. Use `Restore.cmd` from the same package to restore the backed-up files before installing a different release.

The installer preserves `savedata`. Preserving the files alone does not make every old scene save compatible with changed scripts. Read [SAVE-MIGRATION.md](SAVE-MIGRATION.md) before carrying saves across versions.

## Current features

- English script, dictionary, menus, and translated artwork.
- Private ScarlettFont loading for dialogue, names, and backlog.
- Wrapping and layout repairs across the game's different text boxes.
- Voice playback and backlog ambience repairs.
- A persistent **Keep voice** On/Off setting. New voices replace earlier voices; intentional scripted stops and skipping still stop playback.
- A copy-only save converter with verified RC5/RC6-to-RC7 mappings and Japanese-to-English glossary progress mapping.

## Repository contents

- `scarlett_save_migration.py` and `save-migration-maps.json.gz`: standalone converter and compatibility tables. Requires Python 3.10 or newer; no third-party Python packages.
- `Install.cmd`, `Install.ps1`, `Restore.cmd`, `Restore.ps1`, `Installer.Core.ps1`: installer sources, intended for the complete release package with its manifest and payload.
- `SAVE-MIGRATION.md`: supported conversions, commands, and rollback instructions.
- `VALIDATION.md`: exact testing scope and remaining limitations.
- `RELEASES.json`: release file hashes.

This is a curated distribution/tooling repository, not a complete reproduction of the private translation workspace. The original game, extracted scripts, workbook, user saves, personal paths, and private review records are excluded. The complete patch is distributed separately from the repository's source tree.

## Reporting problems

Include the patch version, whether the affected save predates that version, and a screenshot or short description. Do not post personal save folders or logs publicly without checking their contents.

Game artwork, audio, text, and branding remain the property of their respective rights holders. Font notices accompany the packaged font. No new license is assigned to third-party materials by this repository.
