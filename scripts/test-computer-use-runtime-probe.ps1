[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TemporaryRoot
)

$ErrorActionPreference = 'Stop'

$node = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) {
  throw 'node.exe not found; cannot test the Computer Use runtime probe'
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$probe = Join-Path $scriptRoot 'probe-computer-use-runtime.mjs'
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
  throw "Computer Use runtime probe is missing: $probe"
}

$root = [System.IO.Path]::GetFullPath($TemporaryRoot)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$work = Join-Path $root ('computer-use-runtime-probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$encoding = [System.Text.UTF8Encoding]::new($false)

try {
  $validModule = Join-Path $work 'valid-runtime.mjs'
  $invalidModule = Join-Path $work 'invalid-runtime.mjs'
  [System.IO.File]::WriteAllText(
    $validModule,
    'export const sky = { list_windows: async () => [{ app: "msedge.exe", id: 7, title: "fixture" }] };',
    $encoding
  )
  [System.IO.File]::WriteAllText(
    $invalidModule,
    'export const sky = { list_windows: async () => [{ app: "", id: "7", title: "fixture" }] };',
    $encoding
  )

  $validOutput = @(& $node.Source $probe $validModule 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "valid Computer Use runtime fixture failed: $($validOutput -join [Environment]::NewLine)"
  }
  $validResult = ($validOutput | Select-Object -Last 1) | ConvertFrom-Json
  if (
    $validResult.ok -ne $true -or
    $validResult.windowContract -ne $true -or
    [int]$validResult.count -ne 1 -or
    [int]$validResult.invalidWindowCount -ne 0
  ) {
    throw "valid Computer Use runtime fixture returned an unexpected result: $($validOutput -join [Environment]::NewLine)"
  }

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $invalidOutput = @(& $node.Source $probe $invalidModule 2>&1)
    $invalidExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $invalidText = ($invalidOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
  if ($invalidExitCode -eq 0 -or $invalidText -notmatch 'violated the Window contract at indexes 0') {
    throw "invalid Computer Use runtime fixture was not rejected correctly: $invalidText"
  }

  Write-Output 'Computer Use runtime probe contract test passed'
} finally {
  if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
  }
}
