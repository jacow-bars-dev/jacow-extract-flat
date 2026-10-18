# JACoW Extract Flat

A small Windows utility for extracting a ZIP archive's files into one flat folder.
It adds **JACoW: Extract Flat Here** to the classic File Explorer context menu,
with a custom ZIP → arrow → folder icon.

This is an independent utility, not an official JACoW product.

## Files

Only these two files are required to run and install the tool:

- `JACoW-ExtractFlat.ps1` — extraction and context-menu registration.
- `jacow_extract.ico` — context-menu icon; keep it beside the script.

This README documents the tool. Any PNG master artwork and icon-generation prompt
are optional development assets, not runtime requirements.

## Requirements

- Windows with Windows PowerShell 5.1, which is used by the registered command.
- Administrator access to install or remove the machine-wide context-menu entry.

The installer can also be run from PowerShell 7 (`pwsh.exe`). PowerShell 7, Python,
downloaded modules, and a compiled EXE are not required for normal use.

## Install

1. Download the repository using **Code → Download ZIP**, then extract it.
2. Put the script and icon together in a permanent local folder, such as `C:\Tools\JACoW`.
3. To register for the context menu use, open **PowerShell as Administrator** and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\JACoW\JACoW-ExtractFlat.ps1"
```

Registration stores absolute paths. If you move the script or icon, run the
installer again from the new location. Rerunning it updates the same menu entry.

You can substitute `pwsh.exe` for this installation command if PowerShell 7 is
installed. The registered menu command still uses `powershell.exe` internally.
and a brief console flash may occur despite `-WindowStyle Hidden`. To suppress the flash
please read the instructions inside the script file how a small EXE can be generated. 

## Use

Right-click a ZIP file and choose **JACoW: Extract Flat Here**. On Windows 11,
open **Show more options** to find this classic menu command.

For example, `C:\Incoming\papers.zip` extracts into `C:\Incoming\papers\`.
All archive subfolders are flattened: only their files are extracted.

- Matching files in the output folder are overwritten, including read-only files
  that can be made writable with the current user's permissions.
- If multiple archive entries flatten to the same filename, the last entry in
  archive order wins. Windows filename matching is case-insensitive.
- No numbered duplicate copies are created.
- Files absent from the archive remain untouched.
- Empty archive directories are ignored; empty files are retained.
- Unsafe Windows filename characters are replaced, and reserved names are adjusted.
- Directory or symbolic-link conflicts at output filenames cause an error.

Extraction runs with the current user's permissions and does not request elevation.
Extraction is not transactional: successful files remain after a failure, and a
previous matching file may already have been replaced. Failed partial files are removed.
Failures are logged without a dialog to:

```text
%LOCALAPPDATA%\JACoW\ExtractFlat\errors.log
```

You can also extract directly without registering the context menu:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\JACoW\JACoW-ExtractFlat.ps1" "C:\Incoming\papers.zip"
```

You can also create a shortcut to this utility in SendTo folder if administrator account is not available.

```text
Win+R > shell:sendto and create a shortcut to JACoW-ExtractFlat.ps1 in the folder being opened
```

## Remove the context-menu entry

Run in an administrator PowerShell window:

```powershell
Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Classes\SystemFileAssociations\.zip\Shell\ExtractFlat' -Recurse
```

This removes the registration only. It does not delete the script, icon, archives,
or extracted files. SendTo shortcuts created manually are separate.