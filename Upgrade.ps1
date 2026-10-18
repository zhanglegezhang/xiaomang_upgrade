param([string]$App,[string]$Package,[string]$ReleaseTag,[switch]$NonInteractive,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. "$PSScriptRoot/Core.ps1"
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$stage=$null;$helper=$null;$stopped=$false;$mutex=$null;$held=$false
try {
 if($NonInteractive -and (!$App -or !$Package -or !$ReleaseTag)){throw '需要 App、Package 和 ReleaseTag。'}
 if(!$App){$pick=New-Object Windows.Forms.OpenFileDialog;$pick.Title='选择旧版小蟒的 xiaomang.exe';$pick.Filter='小蟒程序|xiaomang.exe';if($pick.ShowDialog() -ne 'OK'){exit};$App=Split-Path $pick.FileName;$pick.Dispose()}
 if(!$Package){$pick=New-Object Windows.Forms.OpenFileDialog;$pick.Title='选择要升级到的官方使用包';$pick.Filter='使用包 ZIP|*.zip';if($pick.ShowDialog() -ne 'OK'){exit};$Package=$pick.FileName;$pick.Dispose()}
 $App=[IO.Path]::GetFullPath($App).TrimEnd('\');$Package=[IO.Path]::GetFullPath($Package)
 Assert-SafePath $App;Assert-SafePath $Package
 if($PSScriptRoot.Equals($App,[StringComparison]::OrdinalIgnoreCase) -or $PSScriptRoot.StartsWith($App+'\',[StringComparison]::OrdinalIgnoreCase)){throw '请将升级工具移到旧程序目录之外再运行。'}
 if($App.StartsWith('\\') -or $Package.StartsWith('\\')){throw '请使用本地磁盘上的程序和使用包。'}
 $entry=Join-Path $App 'xiaomang.exe'
 foreach($required in 'xiaomang.exe','ShareX.dll','Portable'){if(!(Test-Path -LiteralPath (Join-Path $App $required) -PathType Leaf)){throw "旧目录缺少 $required；仅支持标准便携版。"}}
 if(Test-Path -LiteralPath (Join-Path $App 'PersonalPath.cfg')){throw '检测到自定义数据路径。此版本工具不自动迁移该布局，请保留原程序。'}
 if(!(Test-Path -LiteralPath "$PSScriptRoot/install.ps1")){throw '升级工具不完整。'}
 $identity=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($App.ToUpperInvariant())).Replace('/','_')
 $mutex=New-Object Threading.Mutex($false,('Local\XiaomangUniversalUpgrade.'+$identity))
 try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(!$held){throw '该目录已有升级任务。'}
 $oldVersion=Get-ProductVersion ([IO.File]::ReadAllBytes((Join-Path $App 'ShareX.dll')))
 Write-Host '正在检查使用包结构与版本…'
 $plan=Get-ArchivePlan $Package;Assert-Version $oldVersion $plan.Version
 if(!$plan.SupportsStartupCheck){throw '目标使用包不支持升级后数据加载确认。请使用包含升级修复的新使用包；原程序未修改。'}
 if(!$ReleaseTag){
  $name=[IO.Path]::GetFileName($Package)
  if($name -match '(\d{4})-(\d{2})-(\d{2})'){$ReleaseTag='v'+$plan.Version+'-'+$Matches[1]+$Matches[2]+$Matches[3]}
  Add-Type -AssemblyName Microsoft.VisualBasic
  $ReleaseTag=[Microsoft.VisualBasic.Interaction]::InputBox('填写该使用包对应的 GitHub 发布标签（发布页可见）。','确认官方版本标签',$ReleaseTag)
  if(!$ReleaseTag){exit}
 }
 if($ReleaseTag -notmatch '^v(\d+\.\d+)-\d{8}(?:-r\d+)?$' -or [version]$Matches[1] -ne $plan.Version){throw '发布标签与使用包版本不符。'}
 Write-Host '正在向官方发布页核对 SHA256…'
 $repo='https://github.com/zhanglegezhang/xiaomang'
 try {
  $release=Invoke-RestMethod "https://api.github.com/repos/zhanglegezhang/xiaomang/releases/tags/$ReleaseTag" -Headers @{'User-Agent'='Xiaomang-UniversalUpgrade'} -TimeoutSec 30
  if($release.draft -or $release.prerelease -or $release.tag_name -cne $ReleaseTag){throw '不是所选正式发布。'}
  $assets=@($release.assets|Where-Object {$_.name -match ('^xiaomang'+[regex]::Escape($plan.Version.ToString())+'_\d{4}-\d{2}-\d{2}_usage\.zip$')})
  if($assets.Count -ne 1){throw '无法确认唯一官方使用包。'}
  $asset=$assets[0];$sha=$asset.digest -replace '^sha256:','';$size=$asset.size
  if($asset.browser_download_url -cne "$repo/releases/download/$ReleaseTag/$($asset.name)"){throw '发布来源不匹配。'}
 } catch {
  Write-Host '正在通过官方标签下的发布清单核验…'
  $metadata=Invoke-RestMethod "https://raw.githubusercontent.com/zhanglegezhang/xiaomang/$ReleaseTag/docs/RELEASE-$ReleaseTag.json" -TimeoutSec 30
  if($metadata.releaseTag -cne $ReleaseTag){throw '官方发布清单不匹配。'}
  $asset=$metadata.usagePackage;$sha=$asset.sha256;$size=$asset.bytes
  if($asset.url -cne "$repo/releases/download/$ReleaseTag/$($asset.asset)"){throw '发布清单来源不匹配。'}
 }
 if($sha -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-Item -LiteralPath $Package).Length -ne $size -or (Get-FileHash -LiteralPath $Package).Hash -ne $sha){throw '使用包与官方 SHA256 或大小不一致，未修改旧程序。'}
 if($ValidateOnly){Write-Host "PASS official package validated: $oldVersion -> $($plan.Version); no app changes";exit 0}
 if(!$NonInteractive -and [Windows.Forms.MessageBox]::Show("从 $oldVersion 升级到 $($plan.Version)`n原目录：$App`n请先保存并关闭本地日记、输入法设置及正在进行的录屏。`n将完整备份旧目录，保留个人数据和可选组件。不需要安装输入法。",'小蟒通用升级','OKCancel','Information') -ne 'OK'){exit}
 $stage=Join-Path $env:LOCALAPPDATA ('XiaomangUpdates\universal-'+[Guid]::NewGuid().ToString('N'))
 if($stage.StartsWith($App+'\',[StringComparison]::OrdinalIgnoreCase)){throw '升级暂存目录不能位于旧程序内。'}
 Assert-SafePath $stage
 $inputRoot=Join-Path $env:APPDATA 'XiaomangInputMethod'
 $oldSize=Get-TreeSize $App;$inputSize=Get-TreeSize $inputRoot
 Assert-FreeSpace $env:LOCALAPPDATA ($oldSize*2+$inputSize*2+$plan.Bytes*2+512MB)
 Assert-FreeSpace $App ($plan.Bytes+256MB)
 $probe=Join-Path $App ('.upgrade-probe-'+[Guid]::NewGuid().ToString('N'));[IO.File]::WriteAllText($probe,'');[IO.File]::Delete($probe)
 [IO.Directory]::CreateDirectory($stage)|Out-Null
 Start-Transcript -Path (Join-Path $stage 'upgrade.log')|Out-Null
 $privateZip=Join-Path $stage 'verified-package.zip';Copy-Item -LiteralPath $Package -Destination $privateZip
 if((Get-FileHash -LiteralPath $privateZip).Hash -ne $sha){throw '复制后的使用包校验失败。'}
 $payload=Join-Path $stage 'payload';[IO.Directory]::CreateDirectory($payload)|Out-Null
 Expand-CheckedArchive $privateZip $plan $payload $App
 # Other editors must finish saving. Never force-terminate user work.
 foreach($p in Get-Process -ErrorAction Stop){try{$path=$p.Path}catch{continue};if($path -and $path.StartsWith($App+'\',[StringComparison]::OrdinalIgnoreCase) -and $p.ProcessName -in @('xiaomang-diary','qingjian-settings')){throw '请先保存并关闭本地日记和输入法设置，再重试。'}}
 Write-Host '正在正常保存并退出小蟒…'
 $running=@(Get-Process xiaomang -ErrorAction SilentlyContinue|Where-Object Path -eq $entry)
 if($running.Count -gt 1){throw '发现多个小蟒实例，请先关闭多余实例。'}
 if($running.Count){$exitProcess=Start-Process -FilePath $entry -ArgumentList '-ExitShareX' -WindowStyle Hidden -PassThru;foreach($p in $running){if(!$p.WaitForExit(90000)){throw '小蟒尚未完成保存退出，未替换程序。'}};if(!$exitProcess.WaitForExit(5000)){throw '退出请求尚未结束。'}}
 $stopped=$true
 Write-Host '正在备份并校验旧程序与个人数据…'
 Backup-StableTree $App (Join-Path $stage 'old-app-backup.zip')
 Write-Host '正在原样备份输入法数据（未安装组件也可继续）…'
 Backup-StableTree $inputRoot (Join-Path $stage 'input-data-backup.zip')
 if((Get-ProductVersion ([IO.File]::ReadAllBytes((Join-Path $App 'ShareX.dll')))) -ne $oldVersion){throw '备份期间旧程序版本改变。'}
 # Keep the wrapper and its per-directory mutex alive until the transaction ends.
 $snapshot=Write-DataSnapshot $App $inputRoot $stage
 @{App=$App;Stage=$stage;Payload=$payload;Snapshot=$snapshot;ProcessId=2147483647;Started=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $stage 'install.json') -Encoding UTF8
 Write-Host '备份已完成，正在替换程序并验证启动，请勿关闭此窗口…'
 $helper=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$PSScriptRoot+'\install.ps1"'),'-Config',('"'+$stage+'\install.json"'),'-NoUI') -WindowStyle Hidden -PassThru
 while(!$helper.WaitForExit(500)){ }
 $result=Join-Path $stage 'result.txt'
 if(!(Test-Path -LiteralPath $result)){throw "升级助手意外结束，请保留备份并检查目录：$stage"}
 $message=Get-Content -LiteralPath $result -Raw -Encoding UTF8
 Write-Host $message
 Write-Host "备份与日志：$stage"
 Stop-Transcript|Out-Null
 if(!$NonInteractive){[Windows.Forms.MessageBox]::Show(($message+"`n备份与日志："+$stage),'小蟒升级结果','OK','Information')|Out-Null}
 if($message -notmatch '^更新成功'){exit 1}
 exit 0
} catch {
 $reason=$_.Exception.Message
 if($helper -and !$helper.HasExited){Set-Content -LiteralPath (Join-Path $stage 'cancel') -Value cancel;if(!$helper.WaitForExit(5000)){$helper.Kill();$helper.WaitForExit()}}
 if($stopped -and !(Get-Process xiaomang -ErrorAction SilentlyContinue|Where-Object Path -eq $entry)){Start-Process -FilePath $entry -ArgumentList '-silent' -WorkingDirectory $App -WindowStyle Hidden}
 if($stage){try{Stop-Transcript|Out-Null}catch{}}
 if($NonInteractive){Write-Error $reason -ErrorAction Continue}else{[Windows.Forms.MessageBox]::Show("升级未完成：$reason`n请保留备份，并查看 result.txt 确认恢复状态。备份目录：$stage",'小蟒通用升级','OK','Warning')|Out-Null}
 exit 1
} finally {if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
