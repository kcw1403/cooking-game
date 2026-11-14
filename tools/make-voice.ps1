# 음성 mp3 만들기 (Azure Speech TTS)
# docs/음성문장.txt의 문장마다 voice/<mp3 이름>.mp3를 만들고, voice/list.js(VOICE_FILES)를 다시 씁니다.
# - 이미 있는 mp3는 건너뜁니다. 중간에 멈춰도 다시 실행하면 이어서 만듭니다.
# - 키와 지역은 사용자 환경 변수 AZURE_SPEECH_KEY, AZURE_SPEECH_REGION에서 읽습니다. 키를 저장소에 넣지 않습니다.
# - 무료 계층(F0)은 1분에 20건까지라 요청 사이를 3.1초 띄우고, 429(너무 많음)가 오면 60초 기다렸다가 다시 합니다.
# 실행: powershell -ExecutionPolicy Bypass -File tools\make-voice.ps1   (저장소 폴더에서)
param(
  [string]$Voice = 'ko-KR-SunHiNeural',
  [string]$Rate = '0%',
  [double]$Gap = 3.1,
  [switch]$ListOnly   # mp3는 만들지 않고 voice/list.js만 다시 씀
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$table = Join-Path $root ('docs\' + [char]0xC74C + [char]0xC131 + [char]0xBB38 + [char]0xC7A5 + '.txt')   # docs\음성문장.txt
$vdir = Join-Path $root 'voice'
$key = [Environment]::GetEnvironmentVariable('AZURE_SPEECH_KEY', 'User')
$reg = [Environment]::GetEnvironmentVariable('AZURE_SPEECH_REGION', 'User')
if (-not $ListOnly -and (-not $key -or -not $reg)) { throw 'AZURE_SPEECH_KEY / AZURE_SPEECH_REGION 환경 변수가 없습니다.' }

# 문장표 읽기: mp3 이름<TAB>문장<TAB>쓰는 놀이 (#으로 시작하는 줄은 설명)
$rows = Get-Content $table -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object {
  $c = $_ -split "`t"; [pscustomobject]@{ Hash = $c[0]; Text = $c[1] }
}

$uri = "https://$reg.tts.speech.microsoft.com/cognitiveservices/v1"
$headers = @{ 'Ocp-Apim-Subscription-Key' = $key; 'X-Microsoft-OutputFormat' = 'audio-24khz-48kbitrate-mono-mp3'; 'User-Agent' = 'cooking-game-tts' }
$made = 0; $skip = 0; $i = 0
if (-not $ListOnly) {
  foreach ($r in $rows) {
    $i++
    $out = Join-Path $vdir "$($r.Hash).mp3"
    if (Test-Path $out) { $skip++; continue }
    $ssml = "<speak version='1.0' xml:lang='ko-KR'><voice name='$Voice'><prosody rate='$Rate'>$([Security.SecurityElement]::Escape($r.Text))</prosody></voice></speak>"
    for ($try = 1; $try -le 5; $try++) {
      try {
        Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -ContentType 'application/ssml+xml; charset=utf-8' `
          -Body ([Text.Encoding]::UTF8.GetBytes($ssml)) -OutFile $out -UseBasicParsing
        break
      } catch {
        if (Test-Path $out) { Remove-Item $out }
        $code = $_.Exception.Response.StatusCode.value__
        Write-Host "  [$i] $($r.Hash) 실패 ($code), 다시 시도 $try/5"
        Start-Sleep -Seconds ($(if ($code -eq 429) { 60 } else { 10 }))
      }
    }
    if (Test-Path $out) { $made++ }
    if ($i % 20 -eq 0) { Write-Host "[$i/$($rows.Count)] 새로 만듦 $made, 건너뜀 $skip" }
    Start-Sleep -Milliseconds ([int]($Gap * 1000))
  }
}

# voice/list.js 다시 쓰기: mp3가 있는 문장만 넣음
$lines = $rows | Where-Object { Test-Path (Join-Path $vdir "$($_.Hash).mp3") } | ForEach-Object {
  "  '$($_.Hash)': '" + ($_.Text -replace '\\', '\\' -replace "'", "\'") + "',"
}
$js = @(
  '// 음성 mp3 목록: { ''mp3 이름(문장 해시)'': ''문장'' }'
  "// tools/make-voice.ps1이 만듭니다 (음성: $Voice, 빠르기: $Rate). 직접 고치지 않습니다."
  '// 여기에 없는 문장은 기기 음성(Web Speech API)으로 읽습니다.'
  'window.VOICE_FILES = {'
) + $lines + '};'
[IO.File]::WriteAllText((Join-Path $vdir 'list.js'), ($js -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
Write-Host "끝: 새로 만듦 $made, 건너뜀 $skip, 목록 $($lines.Count) / 문장 $($rows.Count)"
