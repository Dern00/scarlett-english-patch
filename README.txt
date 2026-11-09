SCARLETT - ENGLISH PATCH
Version 1.0 - First public release

English scenario text, Cyclopedia, chapter summaries, menus and interface artwork.
ScarlettFont is used throughout dialogue, speaker names and backlog. The chapter
menu has been rearranged for readable labels and consistent spacing.

REQUIREMENTS AND INSTALLATION
1. Close Scarlett. Use a separate copy of the Japanese PC game with both official
   updates applied. Keep the original game and all patch backups intact.
2. Extract this entire ZIP into a folder outside the game folder.
3. Run Install.cmd and choose the game folder. Windows PowerShell is included
   with Windows; Python and internet access are not needed.
4. Launch Scarlett.exe from that English game folder.

The installer verifies the supported game files before replacing Scarlett.exe
and update2.arc. It retains exact originals and a restoration receipt under
Scarlett-English-Patch in the selected folder. Do not delete those backups.
It does not install a system font, change Windows locale or access the network.
Japanese locale or a compatible locale environment is still required.

SAVE DATA
Start a new game with the English patch. Japanese scene saves are unsupported.
Japanese shared progress, such as Cyclopedia registrations, can be converted
when no unsupported scene saves are present. If asked to identify an existing
Japanese profile, select "Original Japanese game (shared progress only)".
Cancel if unsure: the game files and original save profile stay unchanged.

Supported progress is converted in place, with the complete original savedata
folder retained in the installation backup. A version marker identifies this
patch's save format. Read history and unrelated save-folder files are kept.
Unknown layouts and unmapped script positions are refused rather than guessed.
Preserve the whole folder; seek help for an unsupported profile rather than
deleting saves to force installation.

RESTORE AND RECOVERY
Close the game and run Restore.cmd, choosing the same game folder. It restores
the exact pre-install game files and pre-install save profile. Any newer profile
is retained under the selected installation backup as savedata-after-patch.
These newer saves are not converted for the restored Japanese game; keep them for
reinstallation or individual recovery. Restore never merges or discards them.
Unexpected changed files are refused. If installation or restoration was
interrupted, rerun Restore with the same receipt and retain all backups.

VOICE OPTION
Settings has Keep voice: click Change to switch On or Off.
On (default): ordinary dialogue advance lets the current voice finish. A new
voice replaces it; scripted stops and skipping still stop it. Off restores
stopping the voice on advance. Restore Defaults returns the option to On.
Backlog controls preserve ongoing story ambience.

FONT AND ORIGINAL CREDITS
Original game and artwork: nekoneko-software and their respective creators.
ScarlettFont derives from EdensRitterEN, Bree and Sawarabi Mincho. Keep
FONT-NOTICE.txt, OFL-Bree.txt and OFL-SawarabiMincho.txt with the font and patch.
The font loads privately in the game; no system font installation is needed.
