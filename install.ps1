# AItom installer for Windows (DESIGN §4.19 처음 설치, TECH_STACK §8 설치 명령). Run in PowerShell:
#   irm https://raw.githubusercontent.com/nori-sung/aitom-releases/main/install.ps1 | iex
# Files fetched with curl.exe carry no "downloaded from the internet" mark, so SmartScreen does not stop the installer.
# It runs through iex in the user's own PowerShell: `return`, never `exit` (that would close their window).
& {
  trap {
    Write-Host "설치하지 못했습니다: $($_.Exception.Message) (install.ps1 $($_.InvocationInfo.ScriptLineNumber)번째 줄)" -ForegroundColor Red
    return
  }
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  $repo = 'nori-sung/aitom-releases'
  function Say([string]$m) { Write-Host $m }
  function Fail([string]$m) { Write-Host $m -ForegroundColor Red }

  # the chip: .NET's answer, or Windows' own variables where that property is missing (it then reads as empty);
  # PROCESSOR_ARCHITEW6432 is the real one when this PowerShell runs as 32-bit
  try { $os = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" } catch { $os = '' }
  if (-not $os) { $os = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }
  $arch = switch ($os) {
    { $_ -in 'X64', 'AMD64' } { 'x64' }
    'Arm64' { 'arm64' }
    default { $null }
  }
  if (-not $arch) { return Fail 'AItom은 64비트 Windows에만 설치할 수 있습니다.' }

  try {
    $r = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'AItom'; Accept = 'application/vnd.github+json' }
  } catch {
    return Fail 'GitHub에 연결할 수 없습니다.'
  }

  # the same file and SHA-256 the app's updater picks (src/main/update.ts)
  $version = "$($r.tag_name)" -replace '^v', ''
  $name = "AItom-$version-win-$arch.exe"
  $asset = @($r.assets) | Where-Object { $_.name -eq $name } | Select-Object -First 1
  $sha = $null
  if ($asset -and "$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $Matches[1] }
  elseif ($asset -and "$($r.body)" -match "(?im)^([0-9a-f]{64})\s+\*?$([regex]::Escape($name))\s*$") { $sha = $Matches[1] }
  if (-not $sha) { return Fail '최신 릴리스에는 이 컴퓨터에 대한 설치 프로그램이 없습니다.' }

  if (Get-Process AItom -ErrorAction SilentlyContinue) { return Fail 'AItom이 실행 중입니다. AItom을 종료하고 이 명령을 다시 실행하십시오.' }

  $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("aitom-install-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $file = Join-Path $dir $name
  try {
    Say "AItom $version 다운로드 중..."
    & curl.exe -fL --progress-bar -o $file $asset.browser_download_url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file)) { return Fail 'AItom을 다운로드할 수 없습니다.' }
    if ((Get-FileHash -Algorithm SHA256 -Path $file).Hash -ne $sha) { return Fail '다운로드한 파일이 릴리스의 체크섬과 일치하지 않습니다.' }

    Say '설치 중...'
    # per user, into the folder of an earlier install if there is one (electron-builder NSIS), shortcuts included
    $p = Start-Process -FilePath $file -ArgumentList '/S' -Wait -PassThru
    if ($p.ExitCode -ne 0) { return Fail "설치에 실패했습니다(종료 코드 $($p.ExitCode))." }
    Say "설치 완료: AItom $version"
  } finally {
    Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
  }
}
