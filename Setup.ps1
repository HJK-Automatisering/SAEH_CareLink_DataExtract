# Installs everything CareLink Extract needs on this PC. Start it with Setup.bat.
#
#   1. Python 3.14 (64-bit)        for the current user, no admin needed
#   2. Git                         for the current user, no admin needed; used for the automatic updates
#   3. ODBC Driver 18 for SQL Server  machine-wide: Windows asks for admin rights, and you accept Microsoft's license
#   4. This folder as a git clone of the GitHub repo, so CareLinkExtract.bat can update itself
#   5. .venv: a Python 3.14 environment just for this project, with the packages from requirements.txt.
#      CareLinkExtract.bat always uses it, so other Python versions on the PC (like 3.15) do not matter.
#   6. .env from .env.example, and a shortcut on the desktop
#
# Safe to run again: every step checks first and only installs or changes what is missing.
# -Unattended skips opening Notepad and creating the desktop shortcut (for IT or testing).
param([switch]$Unattended)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar in Windows PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PythonVersion = '3.14.10'
$PythonUrl     = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
$GitUrl        = 'https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/Git-2.56.1-64-bit.exe'
$OdbcUrl       = 'https://go.microsoft.com/fwlink/?linkid=2378279'   # ODBC Driver 18 for SQL Server, x64 (also installs the 32-bit driver)
$OdbcDriver    = 'ODBC Driver 18 for SQL Server'
$RepoUrl       = 'https://github.com/HJK-Automatisering/SAEH_CareLink_DataExtract.git'

$ProjectDir  = $PSScriptRoot
$DownloadDir = Join-Path $env:TEMP 'CareLinkSetup'
$Results     = [ordered]@{}

function Write-Step($text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Write-Note($text) { Write-Host "   $text" }

function Get-Installer($Url, $FileName, $Signer) {
    # Download an installer and only use it if it is signed by the expected publisher
    New-Item -ItemType Directory -Force $DownloadDir | Out-Null
    $path = Join-Path $DownloadDir $FileName
    Write-Note "Downloading $FileName..."
    Invoke-WebRequest -Uri $Url -OutFile $path -UseBasicParsing
    $sig = Get-AuthenticodeSignature $path
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike "*$Signer*") {
        Remove-Item $path -Force
        throw "$FileName is not signed by $Signer (signature: $($sig.Status)). It was deleted and not installed."
    }
    return $path
}

function Test-Python314($Exe) {
    # True if $Exe is a working 64-bit Python 3.14
    if (-not $Exe -or -not (Test-Path $Exe)) { return $false }
    $ErrorActionPreference = 'Continue'   # in Windows PowerShell 5.1 any stderr output would otherwise count as a failure
    try {
        $out = & $Exe -c "import sys, struct; print(sys.version_info[:2] == (3, 14) and struct.calcsize('P') == 8)" 2>$null
        return ($LASTEXITCODE -eq 0 -and "$out".Trim() -eq 'True')
    } catch { return $false }
}

function Find-Python314 {
    $candidates = @()
    # Installs registered by the python.org installer (PEP 514), for this user and for all users
    foreach ($root in 'HKCU:\Software\Python\PythonCore', 'HKLM:\Software\Python\PythonCore') {
        foreach ($tag in '3.14', '3.14-64') {
            $key = Join-Path $root "$tag\InstallPath"
            if (Test-Path $key) {
                $item = Get-ItemProperty $key
                if ($item.ExecutablePath) { $candidates += $item.ExecutablePath }
                if ($item.'(default)')    { $candidates += (Join-Path $item.'(default)' 'python.exe') }
            }
        }
    }
    # Usual install folders: python.org installer (per user / all users) and the Python install manager
    $candidates += "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
                   "$env:ProgramFiles\Python314\python.exe",
                   "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe"
    foreach ($exe in $candidates) { if (Test-Python314 $exe) { return $exe } }
    return $null
}

function Find-Git {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($exe in "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe", "$env:ProgramFiles\Git\cmd\git.exe") {
        if (Test-Path $exe) { return $exe }
    }
    return $null
}

function Test-OdbcDriver {
    return [bool](Get-OdbcDriver -Name $OdbcDriver -Platform '64-bit' -ErrorAction SilentlyContinue)
}

function Install-Python {
    Write-Step "1/6  Python 3.14 (64-bit)"
    $py = Find-Python314
    if ($py) { Write-Note "Already installed: $py"; $Results['Python 3.14'] = 'OK (already installed)'; return $py }

    $installer = Get-Installer $PythonUrl "python-$PythonVersion-amd64.exe" 'Python Software Foundation'
    Write-Note "Installing Python $PythonVersion for this user..."
    # PrependPath puts 3.14 first on this user's PATH, so "python" starts 3.14
    $p = Start-Process $installer -Wait -PassThru -ArgumentList '/passive', 'InstallAllUsers=0', 'PrependPath=1',
        'Include_launcher=1', 'InstallLauncherAllUsers=0', 'Include_test=0', 'Include_tcltk=1', 'Include_pip=1'
    if ($p.ExitCode -ne 0) { throw "The Python installer failed with exit code $($p.ExitCode)." }

    $py = Find-Python314
    if (-not $py) { throw "Python $PythonVersion was installed, but python.exe could not be found." }
    Write-Note "Installed: $py"
    $Results['Python 3.14'] = 'OK (installed)'
    return $py
}

function Install-Git {
    Write-Step "2/6  Git"
    $git = Find-Git
    if ($git) { Write-Note "Already installed: $git"; $Results['Git'] = 'OK (already installed)'; return $git }

    $installer = Get-Installer $GitUrl 'Git-64-bit.exe' 'Johannes Schindelin'
    Write-Note "Installing Git for this user..."
    $p = Start-Process $installer -Wait -PassThru -ArgumentList '/SILENT', '/CURRENTUSER', '/NORESTART', '/NOCANCEL', '/SUPPRESSMSGBOXES', '/SP-'
    if ($p.ExitCode -ne 0) { throw "The Git installer failed with exit code $($p.ExitCode)." }

    $git = Find-Git
    if (-not $git) { throw "Git was installed, but git.exe could not be found." }
    # Make it available to the rest of this setup without opening a new window
    $env:PATH = (Split-Path $git) + ';' + $env:PATH
    Write-Note "Installed: $git"
    $Results['Git'] = 'OK (installed)'
    return $git
}

function Install-OdbcDriver {
    Write-Step "3/6  $OdbcDriver"
    if (Test-OdbcDriver) { Write-Note 'Already installed.'; $Results['ODBC driver'] = 'OK (already installed)'; return }

    $msi = Get-Installer $OdbcUrl 'msodbcsql18.msi' 'Microsoft Corporation'
    Write-Note 'The installer opens now. Accept the license, click Install, and allow the admin prompt.'
    Write-Note 'If you do not have admin rights, ask IT to install "ODBC Driver 18 for SQL Server (x64)".'
    $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/i', "`"$msi`""
    if ($p.ExitCode -eq 1602) { $Results['ODBC driver'] = 'NOT INSTALLED (cancelled)'; return }
    if ($p.ExitCode -notin 0, 3010) { $Results['ODBC driver'] = "NOT INSTALLED (installer exit code $($p.ExitCode))"; return }
    if (-not (Test-OdbcDriver)) { $Results['ODBC driver'] = 'NOT INSTALLED (driver not found afterwards)'; return }
    $Results['ODBC driver'] = 'OK (installed)'
}

function Initialize-Repo($Git) {
    Write-Step "4/6  Project files from GitHub"
    Push-Location $ProjectDir
    try {
        if (Test-Path (Join-Path $ProjectDir '.git')) {
            Write-Note 'Already a git clone. Getting the latest version...'
            & $Git pull --ff-only
            if ($LASTEXITCODE -ne 0) { $Results['Project files'] = 'WARNING (could not update, see above)'; return }
            $Results['Project files'] = 'OK (up to date)'
            return
        }
        # A folder downloaded as a ZIP: turn it into a clone in place. Files git does not track (.env) are kept.
        Write-Note "Connecting this folder to $RepoUrl..."
        Write-Note 'If GitHub asks you to sign in, do so with an account that has access to the repo.'
        & $Git init -q -b main;                           if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
        & $Git remote add origin $RepoUrl;                if ($LASTEXITCODE -ne 0) { throw 'git remote add failed.' }
        & $Git fetch -q origin main;                      if ($LASTEXITCODE -ne 0) { throw "Could not download the project from GitHub ($RepoUrl)." }
        & $Git reset -q --hard origin/main;               if ($LASTEXITCODE -ne 0) { throw 'git reset failed.' }
        & $Git branch -q --set-upstream-to=origin/main;   if ($LASTEXITCODE -ne 0) { throw 'git branch failed.' }
        $Results['Project files'] = 'OK (connected to GitHub)'
    } finally { Pop-Location }
}

function Initialize-Venv($Python) {
    Write-Step "5/6  Python packages (.venv with Python 3.14)"
    $venv = Join-Path $ProjectDir '.venv'
    $venvPy = Join-Path $venv 'Scripts\python.exe'
    if ((Test-Path $venv) -and -not (Test-Python314 $venvPy)) {
        Write-Note '.venv uses another Python version. Recreating it with Python 3.14...'
        Remove-Item $venv -Recurse -Force
    }
    if (-not (Test-Path $venvPy)) {
        & $Python -m venv $venv
        if ($LASTEXITCODE -ne 0) { throw 'Could not create .venv.' }
    }
    Write-Note 'Installing packages from requirements.txt...'
    & $venvPy -m pip install -r (Join-Path $ProjectDir 'requirements.txt') --disable-pip-version-check --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the Python packages (see the error above).' }
    $Results['Python packages'] = "OK ($venv)"
}

function Initialize-Settings {
    Write-Step "6/6  Settings and shortcut"
    $envFile = Join-Path $ProjectDir '.env'
    $example = Join-Path $ProjectDir '.env.example'
    if (Test-Path $envFile) {
        $Results['.env'] = 'OK (already there)'
    } elseif (Test-Path $example) {
        Copy-Item $example $envFile
        $Results['.env'] = 'FILL IN: created from .env.example, add the database settings'
        if (-not $Unattended) { Start-Process notepad.exe $envFile }
    } else {
        $Results['.env'] = 'MISSING: copy your .env file into this folder'
    }

    if ($Unattended) { $Results['Shortcut'] = 'skipped (-Unattended)'; return }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CareLink Extract.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $s = $shell.CreateShortcut($lnk)
    $s.TargetPath = Join-Path $ProjectDir 'CareLinkExtract.bat'
    $s.WorkingDirectory = $ProjectDir
    $s.Save()
    $Results['Shortcut'] = "OK ($lnk)"
}

function Main {
    Write-Host "CareLink Extract setup in $ProjectDir"
    $failed = $false
    try {
        $python = Install-Python
        $git = Install-Git
        Install-OdbcDriver
        Initialize-Repo $git
        Initialize-Venv $python
        Initialize-Settings
    } catch {
        $failed = $true
        Write-Host ''
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ''
    Write-Host '== Summary' -ForegroundColor Cyan
    foreach ($k in $Results.Keys) { Write-Host ('   {0,-16} {1}' -f $k, $Results[$k]) }
    Write-Host ''
    if ($failed) {
        Write-Host 'Setup did not finish. Fix the error above and run Setup.bat again.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Setup is done. Start CareLink Extract with CareLinkExtract.bat (or the desktop shortcut).' -ForegroundColor Green
    exit 0
}

# Run only when started as a script, not when dot-sourced (so the functions can be tested on their own)
if ($MyInvocation.InvocationName -ne '.') { Main }
