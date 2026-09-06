# measure-latency.ps1 — 阶段 2.7 SLA 实测：push 一个标记提交，轮询站点直至可见，输出每轮耗时与 p95。
# 用法（本地 Windows，PowerShell 5.1+）：
#   powershell -File scripts\measure-latency.ps1                          # 备案后：域名口径，默认 3 轮
#   powershell -File scripts\measure-latency.ps1 -BaseUrl "http://115.29.208.35" -HostHeader "115.29.208.35" -Rounds 10
# 判据：连续 10 轮 push→可见 p95 < 60 s（docs/plan.md 阶段 2 验收①）；副判据：新内容可搜延迟（阶段 3 验收）。
# 注意：本机探测必须绕过系统代理（curl.exe + --noproxy，K10）；脚本会创建并 revert 一个临时 md（两个普通提交）。
param(
  [string]$BaseUrl = "https://tuanzi-wow.cn",
  [string]$HostHeader = "",                     # 备案前用 IP 直访时填 ECS IP（命中 nginx 的 IPSERVERNAME 分支）
  [int]$Rounds = 3,
  [int]$MaxWaitSec = 150,                       # 单轮等待上限：75s 更新上界 + 余量
  [int]$ProbeEverySec = 3,
  [string]$SlugPrefix = "sla-probe"
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot       # 仓库根（脚本在 scripts/ 下）
Push-Location $repo
$results = @()
$searchResults = @()
try {
  for ($r = 1; $r -le $Rounds; $r++) {
    $marker = "SLA-MARKER-" + [guid]::NewGuid().ToString('N').Substring(0, 12)
    $slug = "{0}-{1}" -f $SlugPrefix, (Get-Date -Format 'HHmmss')
    $file = "content/python/$slug.md"
    # 探针页 front matter 用 here-string 内插生成。禁用「数组元素内 'lit' + (子表达式)」的拼接写法：
    # PS 5.1 对多行数组里该组合的解析会产生值断行/吞元素（D39 实证，探针页因此构建失败过一次）
    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    $md = @"
+++
title = 'SLA 探针 $marker'
slug = "$slug"
date = $now
lastmod = $now
weight = 254
categories = ['Python']
tags = ['sla-probe']
draft = false
+++

本页为自动生成的 SLA 测量探针，标记 $marker，数分钟内自动删除。
"@
    [IO.File]::WriteAllText("$repo\$file", $md, [Text.UTF8Encoding]::new($false))
    git add $file 2>&1 | Out-Null
    git commit -q -m "chore(sla): 探针页 $marker（2.7 实测，脚本自动清理）"
    $t0 = Get-Date
    git push -q origin main                       # 双推 GitHub+Gitee；服务器 poll 从 Gitee 拉取
    if ($LASTEXITCODE -ne 0) { throw "git push 失败（轮 $r），中止本轮" }
    Write-Host ("[轮 $r] 已 push（marker=$marker），开始轮询 {0}/{1}/ ..." -f $BaseUrl.TrimEnd('/'), $slug)

    $url = "{0}/{1}/" -f $BaseUrl.TrimEnd('/'), $slug
    $curlArgs = @('-s', '--noproxy', '*', '-m', '8', '-o', 'NUL', '-w', '%{http_code}')
    if ($HostHeader) { $curlArgs += @('-H', "Host: $HostHeader") }
    $curlArgs += $url

    $elapsed = $null
    while (((Get-Date) - $t0).TotalSeconds -lt $MaxWaitSec) {
      Start-Sleep -Seconds $ProbeEverySec
      $code = & curl.exe @curlArgs 2>$null
      if ("$code" -eq '200') {
        # 二次确认内容里真有本轮标记（防上一轮缓存/同名残留）
        $body = & curl.exe -s --noproxy '*' -m 8 @('-H', "Host: $HostHeader") $url 2>$null
        if ($HostHeader -eq '') { $body = & curl.exe -s --noproxy '*' -m 8 $url 2>$null }
        if ("$body" -match $marker) { $elapsed = [int]((Get-Date) - $t0).TotalSeconds; break }
      }
    }
    if ($null -eq $elapsed) {
      Write-Host ("[轮 $r] FAIL：{0}s 内未见探针页（远端 poll/构建失败？查 /srv/blog/logs/deploy.log）" -f $MaxWaitSec)
      $results += [pscustomobject]@{ Round = $r; Sec = -1 }
    } else {
      Write-Host ("[轮 $r] OK：push→可见 {0} s（判据 <60 s）" -f $elapsed)
      $results += [pscustomobject]@{ Round = $r; Sec = $elapsed }
      # 副判据：新内容可搜延迟（阶段 3：push 后 5 s 内可搜）
      $s0 = Get-Date; $hit = $false
      while (((Get-Date) - $s0).TotalSeconds -lt 30) {
        Start-Sleep -Seconds 2
        $q = "/api/search?q=" + [Uri]::EscapeDataString($marker)
        $api = "{0}{1}" -f $BaseUrl.TrimEnd('/'), $q
        $json = if ($HostHeader) { & curl.exe -s --noproxy '*' -m 8 -H "Host: $HostHeader" $api 2>$null } else { & curl.exe -s --noproxy '*' -m 8 $api 2>$null }
        if ("$json" -match $marker) { $searchResults += [int]((Get-Date) - $s0).TotalSeconds; $hit = $true; break }
      }
      Write-Host ("[轮 $r] 可搜延迟：{0}" -f $(if ($hit) { "{0} s（判据 <5 s）" -f $searchResults[-1] } else { '30 s 内未命中' }))
    }

    # 清理：删探针页并推回（服务器下次构建自动移除该页）
    git rm -q $file 2>&1 | Out-Null
    git commit -q -m "chore(sla): 移除探针页（2.7 实测清理）"
    git push -q origin main
    if ($LASTEXITCODE -ne 0) { Write-Host '[清理] push 失败：请手动 git push（探针页仍在内容里）' }
    Start-Sleep -Seconds 5
  }
} finally {
  Pop-Location
}

Write-Host ''
Write-Host '==== SLA 实测汇总 ===='
$ok = $results | Where-Object { $_.Sec -ge 0 }
$results | ForEach-Object { Write-Host ("轮 {0}: {1}" -f $_.Round, $(if ($_.Sec -ge 0) { "$($_.Sec) s" } else { 'FAIL' })) }
if ($ok.Count -ge 1) {
  $sorted = $ok.Sec | Sort-Object
  $p95 = $sorted[[Math]::Min($sorted.Count - 1, [Math]::Ceiling($sorted.Count * 0.95) - 1)]
  Write-Host ("成功 {0}/{1} ｜ min={2}s max={3}s p95={4}s（取第 {5} 名）｜ 判据 p95<60s：{6}" -f `
    $ok.Count, $results.Count, $sorted[0], $sorted[-1], $p95, ($sorted.Count * 0.95), $(if ($p95 -lt 60) { 'PASS' } else { 'FAIL' }))
}
if ($searchResults.Count -ge 1) {
  $s = $searchResults | Sort-Object
  Write-Host ("可搜延迟：min={0}s max={1}s（判据 <5 s，阶段 3 验收）" -f $s[0], $s[-1])
}
