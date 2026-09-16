[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot 'Update-EpCache.ps1') -RepositoryRoot $repositoryRoot

Push-Location $repositoryRoot
try {
  $safeDirectory = 'safe.directory=' + ($repositoryRoot -replace '\\','/')
  git -c $safeDirectory add cache
  if ($LASTEXITCODE -ne 0) { throw 'Git could not stage the refreshed public cache.' }
  git -c $safeDirectory diff --cached --quiet
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'The EP cache is already current; nothing needs to be published.'
    exit 0
  }
  git -c $safeDirectory commit -m 'Update public EP voting-list cache'
  if ($LASTEXITCODE -ne 0) { throw 'Git could not record the refreshed public cache.' }
  git -c $safeDirectory push
  if ($LASTEXITCODE -ne 0) { throw 'GitHub publication failed. Sign in to GitHub again and retry.' }
  Write-Host 'The refreshed public EP cache was published successfully.'
} finally {
  Pop-Location
}
