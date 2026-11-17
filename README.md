# CareLink_DataExtract
.xls data extract to SQL

## Set up a new PC

1. On GitHub, click **Code → Download ZIP**, and extract it where the program should live (for example `C:\CarelinkExtract`).
2. Double-click **`Setup.bat`** in that folder. It installs what is missing and can be run again at any time:
   - Python 3.14 (64-bit) and Git, for the current user (no admin rights needed)
   - ODBC Driver 18 for SQL Server: accept Microsoft's license and allow the admin prompt, or ask IT to install it
   - connects the folder to GitHub, so the program updates itself (sign in to GitHub if asked)
   - `.venv`: the project's own Python 3.14 with the packages from `requirements.txt`, so other Python versions on the PC do not matter
   - `.env` from `.env.example`, and a **CareLink Extract** shortcut on the desktop
3. Fill in the database settings in `.env` (Setup opens it in Notepad).
4. Start the program with the desktop shortcut or `CareLinkExtract.bat`.

## Updates

`CareLinkExtract.bat` gets the latest version from the `main` branch on GitHub every time it starts, and installs
the Python packages again when `requirements.txt` changes. Do not edit the program files on the PC itself:
local changes block the updates. Make changes on GitHub instead.
