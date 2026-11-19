# Обновява папката BookApp от GitHub (peevbs/bookapp). Не изисква Git.
# Какво прави: сваля последната версия, добавя новите файлове, подменя променените (старите отиват в _stari\дата),
# показва какво е ново и записва същото в Promeni-ot-GitHub.txt. Не пипа МОЯТА_БИБЛИОТЕКА-*.xlsx и raft-arhiv-*.json.
$ErrorActionPreference = 'Stop'
$repo = 'peevbs/bookapp'
$dir = $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$tmp = Join-Path $env:TEMP ('raft-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Write-Host 'Свалям последната версия от GitHub...'
  $zip = Join-Path $tmp 'main.zip'
  Invoke-WebRequest -UseBasicParsing -Uri ("https://github.com/$repo/archive/refs/heads/main.zip") -OutFile $zip
  Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x') -Force
  $src = (Get-ChildItem -Path (Join-Path $tmp 'x') -Directory | Select-Object -First 1).FullName
  $backup = Join-Path $dir ('_stari\' + $stamp)
  $new = @(); $changed = @(); $same = 0
  foreach ($f in Get-ChildItem -Path $src -Recurse -File) {
    $rel = $f.FullName.Substring($src.Length).TrimStart('\')
    $name = Split-Path $rel -Leaf
    if ($name -like '*.xlsx' -and $name -ne 'biblioteka.xlsx') { continue }   # личните ти таблици не се пипат
    if ($name -in @('obnovi.ps1', 'Obnovi-ot-GitHub.bat')) { continue }
    $dest = Join-Path $dir $rel
    if (-not (Test-Path $dest)) {
      New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
      Copy-Item $f.FullName $dest; $new += $rel
    } elseif ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $dest).Hash) {
      $b = Join-Path $backup $rel
      New-Item -ItemType Directory -Path (Split-Path $b) -Force | Out-Null
      Copy-Item $dest $b -Force
      Copy-Item $f.FullName $dest -Force; $changed += $rel
    } else { $same++ }
  }
  # Корици, качени от телефона (covers\new, covers\big): остават СЛЕД копирането на компютъра, а от публичното хранилище се трият.
  # Трие се само ако в папката има файл .gh-token (токен на GitHub с право за запис) и само файлове, които вече са тук и са еднакви.
  $removed = 0; $removeNote = ''
  $tokenFile = Join-Path $dir '.gh-token'
  if (Test-Path $tokenFile) {
    try {
      $tok = (Get-Content $tokenFile -Raw).Trim()
      $H = @{ 'User-Agent' = 'raft-sync'; Authorization = ('Bearer ' + $tok); Accept = 'application/vnd.github+json' }
      foreach ($sub in @('covers/new', 'covers/big')) {
        $list = $null
        try { $list = Invoke-RestMethod -UseBasicParsing -Uri ("https://api.github.com/repos/$repo/contents/$sub" + '?ref=main') -Headers $H } catch { continue }   # папката я няма: нищо за трите
        foreach ($it in @($list)) {
          if ($it.type -ne 'file') { continue }
          $local = Join-Path $dir ($sub.Replace('/', '\') + '\' + $it.name)
          if (-not (Test-Path $local)) { continue }
          # git blob sha1 на локалния файл = sha от GitHub, така се уверяваме, че копието тук е същото
          $bytes = [IO.File]::ReadAllBytes($local)
          $hdr = [Text.Encoding]::ASCII.GetBytes('blob ' + $bytes.Length + [char]0)
          $sha1 = [Security.Cryptography.SHA1]::Create().ComputeHash([byte[]]($hdr + $bytes))
          $hex = -join ($sha1 | ForEach-Object { $_.ToString('x2') })
          if ($hex -ne $it.sha) { continue }
          $body = @{ message = ('Премахнато от публичното хранилище (копие на компютъра): ' + $it.name); sha = $it.sha; branch = 'main' } | ConvertTo-Json
          Invoke-RestMethod -UseBasicParsing -Method Delete -Uri $it.url -Headers $H -Body $body -ContentType 'application/json' | Out-Null
          $removed++
        }
      }
    } catch { $removeNote = 'Не успях да изтрия корици от GitHub: ' + $_.Exception.Message }
  }
  # какво е променено: последните промени от GitHub (записани от Claude)
  $stateFile = Join-Path $dir '.sync-sha'
  $last = ''; if (Test-Path $stateFile) { $last = (Get-Content $stateFile -Raw).Trim() }
  $lines = @()
  try {
    $commits = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$repo/commits?per_page=15" -Headers @{ 'User-Agent' = 'raft-sync' }
    foreach ($c in $commits) {
      if ($last -and $c.sha -eq $last) { break }
      $msg = ($c.commit.message -split "`n")[0]
      $lines += ('  ' + ([datetime]$c.commit.author.date).ToLocalTime().ToString('yyyy-MM-dd HH:mm') + '  ' + $msg)
    }
    if ($commits.Count) { Set-Content -Path $stateFile -Value $commits[0].sha }
  } catch { $lines += '  (не успях да прочета списъка с промени)' }
  $out = @()
  $out += ('Обновяване от GitHub: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
  $out += ('Нови файлове: ' + $new.Count + '; променени: ' + $changed.Count + '; същите: ' + $same)
  if ($new.Count) { $out += 'Нови:'; $out += ($new | ForEach-Object { '  ' + $_ }) }
  if ($changed.Count) { $out += ('Променени (старите са в ' + $backup + '):'); $out += ($changed | ForEach-Object { '  ' + $_ }) }
  if (Test-Path $tokenFile) { $out += ('Премахнати от публичното хранилище (копията са на компютъра): ' + $removed); if ($removeNote) { $out += $removeNote } }
  if ($lines.Count) { $out += 'Какво е ново (промени от GitHub):'; $out += $lines } else { $out += 'Няма нови промени от последния път.' }
  $out | ForEach-Object { Write-Host $_ }
  Add-Content -Path (Join-Path $dir 'Promeni-ot-GitHub.txt') -Value ($out + '') -Encoding UTF8
}
finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
