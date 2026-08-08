[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TemporaryRoot
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $scriptRoot 'install-computer-use-local.ps1'
$tokens = $null
$parseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile(
  $installer,
  [ref]$tokens,
  [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
  throw "Installer has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}
foreach ($statement in $installerAst.EndBlock.Statements) {
  if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
    Invoke-Expression $statement.Extent.Text
  }
}
$script:ConfigBackupBeforeOverwrite = @{}

$root = [System.IO.Path]::GetFullPath($TemporaryRoot)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$fixtureRoot = Join-Path $root ('computer-use-config-preservation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$configPath = Join-Path $fixtureRoot 'config.toml'
$marketplaceRoot = Join-Path $fixtureRoot ("O'Brien-" + '$marketplace')
$source = '\\?\' + $marketplaceRoot
$encoding = [System.Text.UTF8Encoding]::new($false)

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected
  )

  if (-not $Text.Contains($Expected)) {
    throw "Expected config content is missing: $Expected"
  }
}

try {
  $initial = @"
[features]
computer_use = false
keep_existing = "preserve-me"

[plugins."computer-use@openai-bundled"]
enabled = false
custom_setting = "preserve-me"

[plugins."browser@openai-bundled"]
enabled = false

[plugins."chrome@openai-bundled"]
enabled = false

[windows]
sandbox = "restricted"
keep_existing = "preserve-me"
"@
  [System.IO.File]::WriteAllText($configPath, $initial, $encoding)

  Set-TomlTable $configPath '[marketplaces.openai-bundled]' @{
    last_updated = '2026-08-08T00:00:00Z'
    source = $source
    source_type = 'local'
  }
  Set-TomlTableKey $configPath '[plugins."computer-use@openai-bundled"]' 'enabled' $true
  Set-TomlTableKey $configPath '[plugins."browser@openai-bundled"]' 'enabled' $true
  Set-TomlTableKey $configPath '[plugins."chrome@openai-bundled"]' 'enabled' $true
  Set-TomlTableKey $configPath '[features]' 'computer_use' $true
  Set-TomlTableKey $configPath '[windows]' 'sandbox' 'unelevated'

  $content = [System.IO.File]::ReadAllText($configPath, $encoding)
  Assert-Contains $content 'keep_existing = "preserve-me"'
  Assert-Contains $content 'custom_setting = "preserve-me"'
  Assert-Contains $content 'computer_use = true'
  Assert-Contains $content 'enabled = true'
  Assert-Contains $content 'sandbox = "unelevated"'
  Assert-Contains $content 'O''Brien-$marketplace'

  $bytes = [System.IO.File]::ReadAllBytes($configPath)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw 'config.toml unexpectedly has a UTF-8 BOM'
  }

  Test-CodexConfig $configPath $marketplaceRoot

  $duplicatePath = Join-Path $fixtureRoot 'duplicate.toml'
  [System.IO.File]::WriteAllText(
    $duplicatePath,
    "[features]`ncomputer_use = false`ncomputer_use = true`n",
    $encoding
  )
  $duplicateRejected = $false
  try {
    Set-TomlTableKey $duplicatePath '[features]' 'computer_use' $true
  } catch {
    $duplicateRejected = $_.Exception.Message -like '*duplicate TOML key*'
  }
  if (-not $duplicateRejected) {
    throw 'Set-TomlTableKey did not reject a duplicate key'
  }

  Write-Output 'Computer Use TOML preservation regression passed'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
