param(
    [string]$RepoUrl = "https://github.com/Satin7/Library-Host.git",
    [string]$InstallRoot = "$HOME\LibraryHost",
    [string]$GitUser = "",
    [string]$GitEmail = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoDir = Join-Path $InstallRoot "repo"
$vsCodeDir = Join-Path $InstallRoot "vscode"
$vsCodeZip = Join-Path $InstallRoot "vscode.zip"
$vsCodeLauncher = Join-Path $InstallRoot "start-vscode.cmd"
$portableGitDir = Join-Path $InstallRoot "portable-git"
$portableGitZip = Join-Path $InstallRoot "portable-git.zip"

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Ensure-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-ToUserPath([string]$Folder) {
    if (-not (Test-Path $Folder)) {
        return
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentUserPath -and $currentUserPath -split ';' | Where-Object { $_ -eq $Folder }) {
        return
    }

    $newUserPath = if ($currentUserPath) { "$currentUserPath;$Folder" } else { $Folder }
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    $env:Path = "$Folder;$env:Path"
}

function Install-Git() {
    if (Ensure-Command "git") {
        return
    }

    Write-Step "Installing Git"
    if ($DryRun) {
        Write-Host "[dry-run] Install Git via winget or portable archive"
        return
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    if (Ensure-Command "winget") {
        winget install --id Git.Git -e --source winget
        return
    }

    $portableGitUrl = "https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/MinGit-2.45.2-64-bit.zip"
    Invoke-WebRequest -Uri $portableGitUrl -OutFile $portableGitZip
    Expand-Archive -Path $portableGitZip -DestinationPath $portableGitDir -Force

    $gitExe = Join-Path $portableGitDir "cmd\git.exe"
    if (-not (Test-Path $gitExe)) {
        throw "Portable Git was not extracted correctly"
    }

    Add-ToUserPath (Join-Path $portableGitDir "cmd")
}

function Install-VSCode() {
    if (Ensure-Command "code") {
        return
    }

    Write-Step "Preparing VS Code"
    if ($DryRun) {
        Write-Host "[dry-run] Download portable VS Code into $InstallRoot"
        return
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $vsCodeDir -Force | Out-Null

    $archiveUrl = "https://update.code.visualstudio.com/latest/win32-x64-user-stable"
    Invoke-WebRequest -Uri $archiveUrl -OutFile $vsCodeZip
    Expand-Archive -Path $vsCodeZip -DestinationPath $vsCodeDir -Force

    $expandedFolder = Get-ChildItem -Path $vsCodeDir -Directory | Select-Object -First 1
    if (-not $expandedFolder) {
        throw "VS Code archive did not expand into an expected folder"
    }

    $launcherContent = @"
@echo off
set "ROOT=$($expandedFolder.FullName)"
if exist "%ROOT%\Code.exe" (
  start "" "%ROOT%\Code.exe"
) else (
  echo VS Code was not extracted correctly.
  exit /b 1
)
"@
    Set-Content -Path $vsCodeLauncher -Value $launcherContent -Encoding ASCII
}

function Prepare-Repo() {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    if (-not (Test-Path $repoDir)) {
        Write-Step "Cloning repository"
        if ($DryRun) {
            Write-Host "[dry-run] git clone $RepoUrl $repoDir"
        } else {
            git clone $RepoUrl $repoDir
        }
    } else {
        Write-Step "Repository already exists"
    }

    if ($GitUser) {
        git -C $repoDir config user.name $GitUser
    }

    if ($GitEmail) {
        git -C $repoDir config user.email $GitEmail
    }

    git -C $repoDir config pull.rebase false
    git -C $repoDir config init.defaultBranch main
}

Write-Step "Bootstrapping development environment"
Install-Git
Install-VSCode
Prepare-Repo

Write-Step "Finished"
Write-Host "Repository: $repoDir"
Write-Host "VS Code launcher: $vsCodeLauncher"
