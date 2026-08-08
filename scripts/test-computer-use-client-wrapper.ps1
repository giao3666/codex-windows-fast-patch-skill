[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TemporaryRoot
)

$ErrorActionPreference = 'Stop'

$node = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) {
  throw 'node.exe not found; cannot test the Computer Use client wrapper probe'
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$probe = Join-Path $scriptRoot 'probe-computer-use-client.mjs'
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
  throw "Computer Use client wrapper probe is missing: $probe"
}

$root = [System.IO.Path]::GetFullPath($TemporaryRoot)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$work = Join-Path $root ('computer-use-client-wrapper-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$encoding = [System.Text.UTF8Encoding]::new($false)
$oldNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
$oldNodeReplNodeModuleDirs = [Environment]::GetEnvironmentVariable('NODE_REPL_NODE_MODULE_DIRS', 'Process')

try {
  $fixtureClient = Join-Path $work 'fixture-client.mjs'
  $invalidClient = Join-Path $work 'invalid-client.mjs'
  $fixture = @'
export async function setupComputerUseRuntime({ globals = globalThis } = {}) {
  const pipe = globals.nodeRepl.nativePipe;
  const socket = await pipe.createConnection(globals.nodeRepl.env.SKY_CUA_NATIVE_PIPE_DIRECTORY);
  const sky = {
    list_windows: async () => [{ app: "msedge.exe", id: 7, title: "fixture-only" }],
    close: async () => socket.end(),
  };
  globals.sky = sky;
}
'@
  $invalid = @'
export async function setupComputerUseRuntime({ globals = globalThis } = {}) {
  const sky = {
    list_windows: async () => [{ app: "", id: "7", title: "fixture-only" }],
    close: async () => {},
  };
  globals.sky = sky;
  return sky;
}
'@
  [System.IO.File]::WriteAllText($fixtureClient, $fixture, $encoding)
  [System.IO.File]::WriteAllText($invalidClient, $invalid, $encoding)

  [Environment]::SetEnvironmentVariable('NODE_PATH', $work, 'Process')
  [Environment]::SetEnvironmentVariable('NODE_REPL_NODE_MODULE_DIRS', $work, 'Process')
  $validOutput = @(& $node.Source $probe $fixtureClient $work fixture 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "valid client wrapper fixture failed: $($validOutput -join [Environment]::NewLine)"
  }
  if (($validOutput | ForEach-Object { [string]$_ }) -match 'fixture-only') {
    throw 'client wrapper probe leaked a window title in its output'
  }
  $validResult = ($validOutput | Select-Object -Last 1) | ConvertFrom-Json
  if (
    $validResult.ok -ne $true -or
    $validResult.setupCalled -ne $true -or
    $validResult.windowContract -ne $true -or
    [int]$validResult.count -ne 1
  ) {
    throw "valid client wrapper fixture returned an unexpected result: $($validOutput -join [Environment]::NewLine)"
  }

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $invalidOutput = @(& $node.Source $probe $invalidClient $work fixture 2>&1)
    $invalidExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $invalidText = ($invalidOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
  if ($invalidExitCode -eq 0 -or $invalidText -notmatch 'violated the Window contract at indexes 0') {
    throw "invalid client wrapper fixture was not rejected correctly: $invalidText"
  }

  Write-Output 'Computer Use client wrapper regression passed'
} finally {
  if ($null -eq $oldNodePath) {
    Remove-Item Env:\NODE_PATH -ErrorAction SilentlyContinue
  } else {
    [Environment]::SetEnvironmentVariable('NODE_PATH', $oldNodePath, 'Process')
  }
  if ($null -eq $oldNodeReplNodeModuleDirs) {
    Remove-Item Env:\NODE_REPL_NODE_MODULE_DIRS -ErrorAction SilentlyContinue
  } else {
    [Environment]::SetEnvironmentVariable('NODE_REPL_NODE_MODULE_DIRS', $oldNodeReplNodeModuleDirs, 'Process')
  }
  if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
  }
}
