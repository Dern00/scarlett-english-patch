# Windows PowerShell 5.1 / built-in .NET. Offline save conversion for the verified v1 installer.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-Migration { param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Get-MigrationU32 { param([byte[]]$Data, [long]$At)
    Assert-Migration ($At -ge 0 -and $At -le $Data.Length-4) 'Truncated save data.'
    return [BitConverter]::ToUInt32($Data, [int]$At)
}
function Get-MigrationHash { param([byte[]]$Data)
    $h = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($h.ComputeHash($Data))).Replace('-', '').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Assert-MigrationPath { param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    Assert-Migration (-not $full.StartsWith('\\')) 'Choose a local folder, not a network or device path.'
    $item = $full
    while ($item) {
        if (Test-Path -LiteralPath $item) {
            Assert-Migration (((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Linked folders and files are not supported.'
        }
        $parent = [IO.Directory]::GetParent($item)
        if ($null -eq $parent) { break }
        $item = $parent.FullName
    }
    return $full.TrimEnd('\')
}
function Read-MigrationManifest { param([string]$Path)
    $file = [IO.File]::OpenRead($Path)
    try {
        $gzip = New-Object IO.Compression.GZipStream($file, [IO.Compression.CompressionMode]::Decompress)
        try {
            $reader = New-Object IO.StreamReader($gzip, [Text.Encoding]::UTF8)
            try { $m = $reader.ReadToEnd() | ConvertFrom-Json }
            finally { $reader.Dispose() }
        } finally { $gzip.Dispose() }
    } finally { $file.Dispose() }
    Assert-Migration ($m.target -eq 'v1.0') 'These tables do not target v1.0.'
    return $m
}
function Get-MigrationLayout { param([byte[]]$Data)
    Assert-Migration ($Data.Length -ge 16) 'Truncated save header.'
    $sig = [Text.Encoding]::ASCII.GetString($Data, 0, 15)
    $frames = @()
    if ($sig -ceq "MajiroSysV1.100`0") {
        $start = 0x9C58
        $count = [long](Get-MigrationU32 $Data 16)
        $heapsize = [long](Get-MigrationU32 $Data 20)
    } elseif ($sig -ceq "MajiroSavV1.102`0") {
        $depth = Get-MigrationU32 $Data 0x90
        $w = Get-MigrationU32 $Data 0x94; $h = Get-MigrationU32 $Data 0x98
        Assert-Migration ($depth -lt 64 -and $w -le 2048 -and $h -le 2048) 'Invalid save dimensions.'
        $framebase = 0x9FD0 + 3*[long]$w*$h
        $frames = @(0..$depth | ForEach-Object { $framebase + $_*0xA8 })
        $start = $framebase + ($depth+1)*0xA8
        $count = [long](Get-MigrationU32 $Data 0x9C) + [long](Get-MigrationU32 $Data 0xA0) + [long](Get-MigrationU32 $Data 0xA4)
        $heapsize = [long](Get-MigrationU32 $Data 0xA8)
    } else { throw 'Unsupported save signature.' }
    Assert-Migration ($count -le 1000000 -and $heapsize -le 134217728) 'Unreasonable save section size.'
    $heap = $start + $count*16
    Assert-Migration ($heap+$heapsize -eq $Data.Length) 'Save section lengths do not match the file.'
    foreach ($at in $frames) {
        Assert-Migration ([Array]::IndexOf($Data, [byte]0, [int]$at, 128) -ge 0) 'Unterminated script filename.'
    }
    return @{ variables=$start; count=$count; heap=$heap; frames=$frames }
}
function Get-MigrationPositions { param($Spec)
    # Original compact tables contain zlib-compressed little-endian uint32 pairs.
    $bytes = [Convert]::FromBase64String($Spec.position_data)
    Assert-Migration ($bytes.Length -gt 6 -and $bytes[0] -eq 0x78) 'Invalid position table.'
    $compressedStream = New-Object IO.MemoryStream(,$bytes)
    $output = New-Object IO.MemoryStream
    try {
        $compressedStream.Position = 2
        $deflate = New-Object IO.Compression.DeflateStream($compressedStream, [IO.Compression.CompressionMode]::Decompress)
        try { $deflate.CopyTo($output) } finally { $deflate.Dispose() }
        $pairs = $output.ToArray()
    } finally { $compressedStream.Dispose(); $output.Dispose() }
    Assert-Migration ($pairs.Length % 8 -eq 0) 'Invalid position pair length.'
    $positions = @{}
    for ($i=0; $i -lt $pairs.Length; $i+=8) {
        $positions[[BitConverter]::ToUInt32($pairs,$i)] = [BitConverter]::ToUInt32($pairs,$i+4)
    }
    return $positions
}
function Convert-MigrationBytes { param([byte[]]$Data, $Manifest, [string]$Release, [string]$Dictionary, [hashtable]$Cache)
    $info = Get-MigrationLayout $Data
    [byte[]]$out = $Data.Clone()
    $changes = New-Object 'Collections.Generic.List[object]'
    for ($number=0; $number -lt $info.frames.Count; $number++) {
        $at = $info.frames[$number]
        $end = [Array]::IndexOf($Data,[byte]0,[int]$at,128)
        $name = ([BitConverter]::ToString($Data,[int]$at,$end-$at)).Replace('-','').ToLowerInvariant()
        $ref = $Manifest.releases.PSObject.Properties[$Release].Value.scripts.PSObject.Properties[$name]
        Assert-Migration ($null -ne $ref) "Unknown script in frame $number."
        $key = [string]$ref.Value
        $spec = $Manifest.tables.PSObject.Properties[$key].Value
        Assert-Migration ($spec.supported -eq $true) "Unverified script change in frame $number."
        if (-not $Cache.ContainsKey($key)) { $Cache[$key] = Get-MigrationPositions $spec }
        foreach ($relative in @(0x80,0x94,0x98,0x9C,0xA0,0xA4)) {
            [uint32]$pos = Get-MigrationU32 $Data ($at+$relative)
            if ($relative -ne 0x80 -and ($pos -eq 0 -or ($relative -le 0x9C -and $pos -ge 2147483648))) { continue }
            Assert-Migration ($Cache[$key].ContainsKey($pos)) "Unmapped script position in frame $number."
            [uint32]$mapped = $Cache[$key][$pos]
            if ($mapped -ne $pos) {
                [BitConverter]::GetBytes($mapped).CopyTo($out,[int]($at+$relative))
                $changes.Add(@{kind='script_position';frame=$number;field=$relative;old=$pos;new=$mapped})
            }
        }
    }
    $found = 0
    $mapping = $Manifest.dictionaries.PSObject.Properties[$Dictionary].Value
    for ($i=0; $i -lt $info.count; $i++) {
        $at = $info.variables + 16*$i
        if ((Get-MigrationU32 $Data $at) -ne 0x037CA38A) { continue }
        $found++
        Assert-Migration ($found -eq 1 -and (Get-MigrationU32 $Data ($at+4)) -eq 3) 'Unexpected glossary variable type or duplicate.'
        $obj = $info.heap + [long](Get-MigrationU32 $Data ($at+8))
        Assert-Migration ($obj -ge $info.heap -and $obj+20+4536*4 -le $Data.Length) 'Invalid glossary array bounds.'
        Assert-Migration ((Get-MigrationU32 $Data ($obj+8)) -eq 3 -and (Get-MigrationU32 $Data ($obj+12)) -eq 14 -and (Get-MigrationU32 $Data ($obj+16)) -eq 108) 'Unsupported glossary dimensions.'
        for ($index=0; $index -lt 4536; $index++) {
            $cell = $obj+20+4*$index
            [uint32]$old = Get-MigrationU32 $Data $cell
            if ($old -eq 0) { continue }
            $property = $mapping.PSObject.Properties[[string]$old]
            Assert-Migration ($null -ne $property) 'Glossary indexes do not match the selected source layout.'
            [uint32]$new = $property.Value
            if ($old -ne $new) {
                [BitConverter]::GetBytes($new).CopyTo($out,[int]$cell)
                $changes.Add(@{kind='glossary_index';cell=$index;old=$old;new=$new})
            }
        }
    }
    $null = Get-MigrationLayout $out
    return @{ data=$out; changes=@($changes.ToArray()) }
}

# Installer transaction extension. Built-in .NET only; no downloads or Python.
function Get-SaveMigrationReceipt { param($Receipt)
    $p=$Receipt.PSObject.Properties['save_migration']
    if ($null -eq $p) { return $null }; return $p.Value
}
function Get-SaveProfileSnapshot { param([string]$Folder)
    if (-not [IO.Directory]::Exists($Folder)) { return @() }
    Assert-CleanPath $Folder
    $out=@()
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -Force | Sort-Object Name)) {
        if ($f.PSIsContainer -or (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Unexpected subfolder or linked file in savedata.' }
        $out += [pscustomobject]@{path=$f.Name;size=$f.Length;sha256=(Get-Sha $f.FullName);attributes=[int]$f.Attributes;creation_utc=$f.CreationTimeUtc.ToString('o');write_utc=$f.LastWriteTimeUtc.ToString('o')}
    }
    return $out
}
function Assert-SaveProfileSnapshot { param([string]$Folder,$Expected)
    $actual=@(Get-SaveProfileSnapshot $Folder);$expectedRows=@($Expected)
    if ($actual.Count -ne $expectedRows.Count) { throw 'Save profile changed or backup is incomplete.' }
    foreach ($e in $expectedRows) {
        $match=@($actual | Where-Object {$_.path -ceq $e.path})
        if ($match.Count -ne 1 -or $match[0].sha256 -ne $e.sha256 -or $match[0].size -ne $e.size) { throw 'Save profile changed or backup hash mismatch.' }
    }
}
function Copy-SaveProfileVerified { param([string]$Source,[string]$Destination,$Snapshot)
    New-Directory $Destination
    foreach ($e in @($Snapshot)) {
        $dst=Join-Safe $Destination $e.path;Copy-NewVerified (Join-Safe $Source $e.path) $dst $e
        Set-OriginalMetadata $dst $e
    }
    Assert-SaveProfileSnapshot $Destination $Snapshot
}
function Select-SaveMigrationOrigin { param([string]$Suggested)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form=New-Object Windows.Forms.Form
    $form.Text='Scarlett - Existing saves';$form.ClientSize=New-Object Drawing.Size(600,235);$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false
    $label=New-Object Windows.Forms.Label;$label.SetBounds(20,15,560,78)
    $label.Text='Choose the version that created your existing scene saves. The installer will convert supported saves in place and keep the complete original folder as a backup. If unsure, Cancel: your saves and game files will stay unchanged.';$form.Controls.Add($label)
    $combo=New-Object Windows.Forms.ComboBox;$combo.DropDownStyle='DropDownList';$combo.SetBounds(20,99,555,28)
    $versions=@('japanese','rc5','rc6','rc7','rc8','test-2026-11-07','v1.0');$titles=@('Original Japanese game (shared progress only)','RC5','RC6','RC7','RC8','Private test build - 7 November 2026','v1.0')
    $null=$combo.Items.AddRange($titles);$combo.SelectedIndex=[Array]::IndexOf($versions,$Suggested);$form.Controls.Add($combo)
    $check=New-Object Windows.Forms.CheckBox;$check.SetBounds(20,139,555,27);$check.Text='My glossary progress was carried over from the Japanese game.';$check.Checked=($Suggested -eq 'japanese');$form.Controls.Add($check)
    $ok=New-Object Windows.Forms.Button;$ok.Text='Continue';$ok.SetBounds(365,187,100,28);$ok.DialogResult=[Windows.Forms.DialogResult]::OK;$form.Controls.Add($ok)
    $cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancel';$cancel.SetBounds(475,187,100,28);$cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel;$form.Controls.Add($cancel);$form.AcceptButton=$ok;$form.CancelButton=$cancel
    try {
        if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK -or $combo.SelectedIndex -lt 0) { throw 'Save conversion cancelled. Original saves and game files were not changed.' }
        $release=$versions[$combo.SelectedIndex];$dictionary=if($check.Checked){'japanese'}else{$release}
        return @{release=$release;dictionary=$dictionary}
    } finally {$form.Dispose()}
}
function Prepare-InstallerSaveMigration { param($Root,$Package,$Manifest,$Transaction,$Receipt,$Journal,[string]$SourceRelease,[string]$SourceDictionary)
    $mapPath=Join-Safe $Package 'save-migration-maps.json.gz';$maps=Read-MigrationManifest $mapPath
    $target=@($Manifest.targets | Where-Object {$_.path -ceq 'update2.arc'})[0]
    Assert-Migration ($maps.target_archive_sha256 -eq $target.sha256) 'Save tables do not match this patch build.'
    $folder=Join-Safe $Root 'savedata';$had=[IO.Directory]::Exists($folder);$snapshot=@(Get-SaveProfileSnapshot $folder)
    $saveBytes=[Int64]0;foreach($e in $snapshot){$saveBytes += [Int64]$e.size};Assert-Space $Root $saveBytes
    $held=New-Object 'Collections.Generic.List[IDisposable]';$cache=@{};$outputs=@{};$reports=@()
    try {
        foreach ($e in $snapshot) {
            # Deny writes while allowing our directory rename during commit.
            $stream=[IO.File]::Open((Join-Safe $folder $e.path),[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete));$held.Add($stream)
        }
        $detected=$maps.archive_releases.PSObject.Properties[(Get-Sha (Join-Safe $Root 'update2.arc'))]
        $suggested=if($null -ne $detected){[string]$detected.Value}else{''}
        $marker=Join-Safe $folder 'scarlett-save-version.json'
        if ($had -and (Test-Path -LiteralPath $marker)) {
            $tag=Read-Json $marker
            if ($tag.format -eq 1 -and $tag.archive_sha256 -eq (Get-Sha (Join-Safe $Root 'update2.arc'))) { $SourceRelease=[string]$tag.release;$SourceDictionary=[string]$tag.dictionary }
        }
        if ($snapshot.Count -gt 0 -and -not $SourceRelease) { $chosen=Select-SaveMigrationOrigin $suggested;$SourceRelease=$chosen.release;$SourceDictionary=$chosen.dictionary }
        if (-not $SourceRelease) { $SourceRelease=$suggested }
        if (-not $SourceDictionary) { $SourceDictionary=$SourceRelease }
        if ($snapshot.Count -gt 0) {
            Assert-Migration ($null -ne $maps.releases.PSObject.Properties[$SourceRelease]) 'Unsupported source save version.'
            Assert-Migration ($null -ne $maps.dictionaries.PSObject.Properties[$SourceDictionary]) 'Unsupported source glossary layout.'
        }
        foreach ($e in $snapshot) {
            [byte[]]$data=[IO.File]::ReadAllBytes((Join-Safe $folder $e.path))
            if ([IO.Path]::GetExtension($e.path) -ieq '.sav' -or $e.path -ieq 'majiro_system.mss') {
                $result=Convert-MigrationBytes $data $maps $SourceRelease $SourceDictionary $cache
            } else { $result=@{data=$data;changes=@()} }
            $outputs[$e.path]=$result.data;$reports += @{path=$e.path;before=$e.sha256;after=(Get-MigrationHash $result.data);changed_fields=$result.changes.Count}
        }
        $version=@{format=1;release=$maps.target;dictionary=$maps.target;archive_sha256=$maps.target_archive_sha256}
        $outputs['scarlett-save-version.json']=[Text.Encoding]::UTF8.GetBytes(($version | ConvertTo-Json -Compress))
        $prepared=Join-Safe $Transaction 'savedata-converted';New-Directory $prepared
        foreach ($name in $outputs.Keys) {
            $dst=Join-Safe $prepared $name;Write-NewBytes $dst $outputs[$name]
            $old=@($snapshot | Where-Object {$_.path -ceq $name})
            if ($old.Count -eq 1) { Set-OriginalMetadata $dst $old[0] }
        }
        Assert-SaveProfileSnapshot $folder $snapshot
        $migration=[pscustomobject]@{state='prepared';had_savedata=$had;source_release=$SourceRelease;source_dictionary=$SourceDictionary;target_release=$maps.target;before=$snapshot;after=@(Get-SaveProfileSnapshot $prepared);files=$reports;post_restore_folder='savedata-after-patch';post_restore_snapshot=@();recovery_note=''}
        $Receipt.save_migration=$migration;Write-Journal $Receipt $Journal;Invoke-TestHook 'AfterSavePrepared'
        return @{held=$held;migration=$migration}
    } catch {foreach($s in $held){$s.Dispose()};throw}
}
function Publish-InstallerSaveMigration { param($Root,$Transaction,$Receipt,$Journal,$Plan)
    $m=Get-SaveMigrationReceipt $Receipt;if($null -eq $m){return}
    $live=Join-Safe $Root 'savedata';$before=Join-Safe $Transaction 'savedata-before';$prepared=Join-Safe $Transaction 'savedata-converted'
    # Windows can refuse a directory rename even when child handles share Delete.
    # Release preparation locks, verify again, then verify the renamed backup too.
    Close-InstallerSaveHandles $Plan
    Assert-SaveProfileSnapshot $live $m.before;Assert-SaveProfileSnapshot $prepared $m.after
    $m.state='publishing';Write-Journal $Receipt $Journal
    if($m.had_savedata){[IO.Directory]::Move($live,$before)}
    if($m.had_savedata){Assert-SaveProfileSnapshot $before $m.before}
    $m.state='original_backed_up';Write-Journal $Receipt $Journal;Invoke-TestHook 'AfterSaveBackupMove'
    [IO.Directory]::Move($prepared,$live)
    $m.state='published';Write-Journal $Receipt $Journal;Invoke-TestHook 'AfterSavePublished'
}
function Close-InstallerSaveHandles { param($Plan)
    if($null -ne $Plan){foreach($s in $Plan.held){$s.Dispose()};$Plan.held.Clear()}
}
function Undo-InstallerSaveMigration { param($Root,$Transaction,$Receipt,$Journal)
    $m=Get-SaveMigrationReceipt $Receipt;if($null -eq $m){return}
    $live=Join-Safe $Root 'savedata';$before=Join-Safe $Transaction 'savedata-before';$failed=Join-Safe $Transaction 'savedata-failed-install'
    if($m.state -eq 'prepared' -or ($m.had_savedata -and -not (Test-Path -LiteralPath $before))){
        Assert-SaveProfileSnapshot $live $m.before;$m.state='rolled_back';Write-Journal $Receipt $Journal;return
    }
    if(Test-Path -LiteralPath $live){Assert-SaveProfileSnapshot $live $m.after;[IO.Directory]::Move($live,$failed)}
    if($m.had_savedata){Assert-SaveProfileSnapshot $before $m.before;[IO.Directory]::Move($before,$live)}
    $m.state='rolled_back';Write-Journal $Receipt $Journal
}
function Assert-InstallerSaveRestore { param($Root,$Transaction,$Receipt)
    $m=Get-SaveMigrationReceipt $Receipt;if($null -eq $m -or $m.state -in @('restored','rolled_back')){return}
    if($m.state -eq 'prepared' -or ($m.state -eq 'publishing' -and -not (Test-Path -LiteralPath (Join-Safe $Transaction 'savedata-before')))){
        Assert-SaveProfileSnapshot (Join-Safe $Root 'savedata') $m.before;return
    }
    if($m.had_savedata){Assert-SaveProfileSnapshot (Join-Safe $Transaction 'savedata-before') $m.before}
    $live=Join-Safe $Root 'savedata';if(Test-Path -LiteralPath $live){$null=Get-SaveProfileSnapshot $live}
}
function Restore-InstallerSaveMigration { param($Root,$Transaction,$Receipt,$Journal)
    $m=Get-SaveMigrationReceipt $Receipt;if($null -eq $m -or $m.state -in @('restored','rolled_back')){return}
    $live=Join-Safe $Root 'savedata';$before=Join-Safe $Transaction 'savedata-before';$after=Join-Safe $Transaction $m.post_restore_folder;$stage=Join-Safe $Transaction 'savedata-restore'
    Assert-InstallerSaveRestore $Root $Transaction $Receipt
    if($m.state -eq 'prepared' -or ($m.state -eq 'publishing' -and -not (Test-Path -LiteralPath $before))){
        $m.state='rolled_back';Write-Journal $Receipt $Journal;return
    }
    if($m.had_savedata -and -not (Test-Path -LiteralPath $stage)){
        $saveBytes=[Int64]0;foreach($e in @($m.before)){$saveBytes += [Int64]$e.size};Assert-Space $Root $saveBytes
        Copy-SaveProfileVerified $before $stage $m.before
    }
    if(Test-Path -LiteralPath $live){
        if(Test-Path -LiteralPath $after){
            # A completed profile publish interrupted before its journal update.
            if($m.had_savedata){Assert-SaveProfileSnapshot $live $m.before}else{throw 'Unexpected save folder during resumed restore.'}
            $m.state='restored';Write-Journal $Receipt $Journal;return
        }
        $m.post_restore_snapshot=@(Get-SaveProfileSnapshot $live)
        $m.state='restoring';Write-Journal $Receipt $Journal;[IO.Directory]::Move($live,$after);Invoke-TestHook 'RestoreAfterSaveBackupMove'
    }
    if($m.had_savedata){[IO.Directory]::Move($stage,$live);Assert-SaveProfileSnapshot $live $m.before}
    $m.state='restored';Write-Journal $Receipt $Journal
}
