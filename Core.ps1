# Windows PowerShell 5.1; no installed .NET SDK or input method required.
function Assert-SafePath([string]$Path) {
 for($p=[IO.Path]::GetFullPath($Path);$p;$p=[IO.Path]::GetDirectoryName($p)) {
  if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "路径包含链接：$p"}
 }
}
function Get-ProductVersion([byte[]]$Bytes) {
 # Read only embedded text; never load or execute the supplied assembly.
 $text=[Text.Encoding]::UTF8.GetString($Bytes)
 $header='小蟒版本日志';$start=$text.IndexOf($header,[StringComparison]::Ordinal)
 if($start -lt 0){throw '无法识别产品版本日志；不支持此版本结构。'}
 $match=[regex]::Match($text.Substring($start),'\d{4}-\d{2}-\d{2}｜(\d+\.\d+)｜(?:新增|优化|修复)｜')
 if(!$match.Success){throw '无法识别产品版本。'}
 return [version]$match.Groups[1].Value
}
function Assert-Version([version]$Old,[version]$New) {
 if($Old.Major -ne 2 -or $New.Major -ne 2 -or $Old.Minor -lt 6){throw '当前工具支持 2.6 起的 2.x 标准便携版；跨大版本或旧结构需更新工具。'}
 if($New -le $Old){throw "目标版本 $New 必须高于当前版本 $Old，不执行降级或同版覆盖。"}
}
function Get-ArchivePlan([string]$ZipPath) {
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($ZipPath)
 try {
  if($zip.Entries.Count -gt 10000){throw '文件数超过上限。'}
  $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $entries=New-Object 'Collections.Generic.List[object]';$prefix=$null;$bytes=0L;$version=$null
  foreach($item in $zip.Entries) {
   if(!$item.Name){continue}
   $parts=$item.FullName.Split('/')
   if($parts.Count -lt 2 -or $parts -contains '' -or $parts -contains '..' -or $parts -contains '.' -or $item.FullName -match '[:\\\x00-\x1f]'){throw '包内路径无效。'}
   foreach($part in $parts){if($part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw '包内文件名不兼容。'}}
   if(!$prefix){$prefix=$parts[0]};if($prefix -cne $parts[0]){throw '使用包应只有一个根目录。'}
   $rel=($parts|Select-Object -Skip 1)-join '\'
   if(!$seen.Add($rel)){throw '包内存在重复路径。'}
   if($rel -match '(?i)(^|\\)(xiaomangtongxue|ApplicationConfig.json|HotkeysConfig.json|PersonalPath.cfg|SpeechModels|XiaomangInputMethod|ffmpeg.exe|ffprobe.exe)(\\|$)'){throw '包内包含用户数据或按需组件，不支持覆盖。'}
   $bytes+=$item.Length
   if($bytes -gt 2GB -or (($item.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw '解压大小超限或含链接。'}
   if($rel -ieq 'ShareX.dll') {
    if($item.Length -gt 64MB){throw '主程序大小异常。'}
    $stream=$item.Open();$memory=New-Object IO.MemoryStream
    try {$stream.CopyTo($memory);$version=Get-ProductVersion $memory.ToArray()}finally{$stream.Dispose();$memory.Dispose()}
   }
   $entries.Add([pscustomobject]@{Name=$item.FullName;Relative=$rel;Bytes=$item.Length})
  }
  foreach($required in 'xiaomang.exe','ShareX.dll','ShareX.runtimeconfig.json','ShareX.deps.json','Portable'){if(!$seen.Contains($required)){throw "缺少必需文件：$required"}}
  return [pscustomobject]@{Version=$version;Bytes=$bytes;Entries=$entries.ToArray()}
 } finally {$zip.Dispose()}
}
function Expand-CheckedArchive($ZipPath,$Plan,$Payload,$App) {
 $zip=[IO.Compression.ZipFile]::OpenRead($ZipPath)
 try {
  foreach($item in $Plan.Entries) {
   $output=[IO.Path]::GetFullPath((Join-Path $Payload $item.Relative))
   if(!$output.StartsWith($Payload+'\',[StringComparison]::OrdinalIgnoreCase)){throw '解压路径越界。'}
   Assert-SafePath (Join-Path $App $item.Relative)
   [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))|Out-Null
   [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry($item.Name),$output)
  }
 }finally{$zip.Dispose()}
}
function Get-TreeSize([string]$Root) {
 if(!(Test-Path -LiteralPath $Root)){return 0L}
 Assert-SafePath $Root
 $size=0L
 foreach($file in Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop){Assert-SafePath $file.FullName;if(!$file.PSIsContainer){$size+=$file.Length}}
 return $size
}
function Assert-FreeSpace([string]$Path,[long]$Required) {
 $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Path))
 if($drive.AvailableFreeSpace -lt $Required){throw ('磁盘空间不足：'+$drive.Name+'，至少需要 '+[math]::Ceiling($Required/1MB)+' MB。')}
}
function Backup-StableTree([string]$Root,[string]$Output) {
 if(!(Test-Path -LiteralPath $Root)){return}
 $before=@{}
 foreach($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force){Assert-SafePath $file.FullName;$before[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName).Hash}
 [IO.Compression.ZipFile]::CreateFromDirectory($Root,$Output,[IO.Compression.CompressionLevel]::Fastest,$false)
 $zip=[IO.Compression.ZipFile]::OpenRead($Output)
 try {
  $count=0
  foreach($item in $zip.Entries){if(!$item.Name){continue};$count++;$path=Join-Path $Root $item.FullName;$stream=$item.Open();$sha=[Security.Cryptography.SHA256]::Create()
   try{$hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$sha.Dispose();$stream.Dispose()}
   if(!$before.ContainsKey($path) -or $hash -ne $before[$path] -or (Get-FileHash -LiteralPath $path).Hash -ne $hash){throw '备份期间数据发生变化，请关闭编辑窗口后重试。'}
  }
  if($count -ne $before.Count -or @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force).Count -ne $count){throw '备份期间文件数量变化。'}
 }finally{$zip.Dispose()}
}
