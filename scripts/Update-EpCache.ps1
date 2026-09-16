[CmdletBinding()]
param(
  [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$votesUrl = 'https://www.europarl.europa.eu/plenary/en/votes.html'
$cacheRoot = Join-Path $RepositoryRoot 'cache'
$filesRoot = Join-Path $cacheRoot 'files'
$manifestPath = Join-Path $cacheRoot 'manifest.json'
$statusPath = Join-Path $cacheRoot 'status.json'
$pagePath = Join-Path $cacheRoot 'votes.html'
$maximumBytes = 25MB

New-Item -ItemType Directory -Force $filesRoot | Out-Null

function Get-Sha256Hex([byte[]]$Bytes) {
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-HeaderValue($Headers, [string]$Name) {
  $value = $Headers[$Name]
  if ($null -eq $value) { return '' }
  if ($value -is [System.Array]) { return [string]::Join(', ', $value) }
  return [string]$value
}

function Write-JsonFile([string]$Path, $Value) {
  $json = $Value | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

$checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
try {
  $pageResponse = Invoke-WebRequest -UseBasicParsing -Uri $votesUrl -TimeoutSec 40
  if ([int]$pageResponse.StatusCode -ne 200) { throw "EP publication page returned HTTP $($pageResponse.StatusCode)." }
  $pageBytes = $pageResponse.RawContentStream.ToArray()
  if ($pageBytes.Length -eq 0 -or $pageBytes.Length -gt $maximumBytes) { throw 'EP publication page returned an invalid response size.' }
  $pageText = [Text.Encoding]::UTF8.GetString($pageBytes)
  if ($pageText -notmatch 'sedcms/votingList/' -or $pageText -notmatch 'collapsible') { throw 'EP returned an access or error page instead of the voting-list catalogue.' }
  [IO.File]::WriteAllBytes($pagePath, $pageBytes)

  $oldManifest = if (Test-Path $manifestPath) { Get-Content -Raw $manifestPath | ConvertFrom-Json } else { $null }
  $known = @{}
  foreach ($entry in @($oldManifest.entries)) { $known[[string]$entry.url] = $entry }

  $currentUrls = [ordered]@{}
  foreach ($link in @($pageResponse.Links)) {
    $href = [string]$link.href
    if (-not $href) { continue }
    try { $uri = [Uri]::new([Uri]$votesUrl, $href) } catch { continue }
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'www.europarl.europa.eu') { continue }
    if ($uri.AbsolutePath -notmatch '^/sedcms/votingList/[^/]+\.docx$') { continue }
    $currentUrls[$uri.AbsoluteUri] = $true
  }
  if ($currentUrls.Count -eq 0) { throw 'No published DOCX voting lists were found; the EP page format may have changed.' }

  $entries = @()
  $downloaded = 0
  $unchanged = 0
  foreach ($url in $currentUrls.Keys) {
    $prior = $known[$url]
    $headers = @{}
    if ($prior -and $prior.etag) { $headers['If-None-Match'] = [string]$prior.etag }
    if ($prior -and $prior.lastModified) { $headers['If-Modified-Since'] = [string]$prior.lastModified }
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -TimeoutSec 40 -SkipHttpErrorCheck
    $statusCode = [int]$response.StatusCode
    if ($statusCode -eq 304 -and $prior) {
      $prior.checkedAt = $checkedAt
      $prior.active = $true
      $entries += $prior
      $unchanged++
      continue
    }
    if ($statusCode -ne 200) { throw "EP voting list returned HTTP ${statusCode}: $url" }
    $bytes = $response.RawContentStream.ToArray()
    if ($bytes.Length -lt 4 -or $bytes.Length -gt $maximumBytes -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4b) {
      throw "EP returned an invalid DOCX response: $url"
    }
    $sha256 = Get-Sha256Hex $bytes
    $urlHash = Get-Sha256Hex ([Text.Encoding]::UTF8.GetBytes($url))
    $relativePath = 'cache/files/' + $urlHash.Substring(0, 32) + '.docx'
    $destination = Join-Path $RepositoryRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    [IO.File]::WriteAllBytes($destination, $bytes)
    $query = [Web.HttpUtility]::ParseQueryString($uri.Query)
    $version = [string]$query['version']
    if (-not $version) { $version = 'Unlabelled' }
    $changedAt = if ($prior -and $prior.sha256 -eq $sha256) { [string]$prior.changedAt } else { $checkedAt }
    $entries += [ordered]@{
      url = $url
      version = $version
      sourceFileName = [Uri]::UnescapeDataString([IO.Path]::GetFileName($uri.AbsolutePath))
      cachePath = $relativePath
      sha256 = $sha256
      bytes = $bytes.Length
      etag = Get-HeaderValue $response.Headers 'ETag'
      lastModified = Get-HeaderValue $response.Headers 'Last-Modified'
      checkedAt = $checkedAt
      changedAt = $changedAt
      active = $true
    }
    if ($prior -and $prior.sha256 -eq $sha256) { $unchanged++ } else { $downloaded++ }
  }

  foreach ($prior in @($oldManifest.entries)) {
    if ($currentUrls.Contains([string]$prior.url)) { continue }
    $prior.active = $false
    $entries += $prior
  }

  $entries = @($entries | Sort-Object -Property @{ Expression = { -not $_.active } }, url)
  $manifest = [ordered]@{
    schemaVersion = 1
    sourceUrl = $votesUrl
    checkedAt = $checkedAt
    pageSha256 = Get-Sha256Hex $pageBytes
    activeUrls = @($currentUrls.Keys)
    entries = $entries
  }
  Write-JsonFile $manifestPath $manifest
  Write-JsonFile $statusPath ([ordered]@{
    ok = $true
    checkedAt = $checkedAt
    activeDocuments = $currentUrls.Count
    downloadedOrChanged = $downloaded
    unchanged = $unchanged
    message = "EP check completed: $($currentUrls.Count) active DOCX files; $downloaded new or changed."
  })
  Write-Host "EP check completed: $($currentUrls.Count) active DOCX files; $downloaded new or changed."
} catch {
  Write-JsonFile $statusPath ([ordered]@{
    ok = $false
    checkedAt = $checkedAt
    message = $_.Exception.Message
  })
  throw
}
