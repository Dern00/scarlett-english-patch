# Built-in Windows PowerShell 5.1/.NET only. No game launch, registry or network; verified transactional save conversion.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Owner = 'ScarlettEnglishPatchInstallerV1'
$script:JournalHash = $null
$script:TargetNames = @('Scarlett.exe', 'update2.arc')
$script:DependencyNames = @('data.arc','data1.arc','data2.arc','fastdata.arc','fastdata1.arc','scenario.arc','slowdata1.arc','slowdata2.arc','slowdata5.arc','stream.arc','update.arc','voice1.arc','voice2.arc','voice3.arc','voice4.arc')
$script:InstallerNames = @('Install.ps1','Restore.ps1','Installer.Core.ps1','Install.cmd','Restore.cmd')
$script:SupportNames = @('README.txt','fonts/ScarlettFont.ttf','fonts/FONT-NOTICE.txt','fonts/OFL-Bree.txt','fonts/OFL-SawarabiMincho.txt')
function Invoke-TestHook { param($Name) } # Production no-op; fixture harness patches only its disposable copy.
function New-InstallId { return [Guid]::NewGuid().ToString('N') }
function Get-FreeBytes { param($Root) return ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Root))).AvailableFreeSpace }
function Get-Sha {
    param($Path)
    $hasher=[Security.Cryptography.SHA256]::Create()
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
}
function Assert-CleanPath {
    param([string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point refused: $cursor" }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
}
function Get-Root {
    param([string]$Path)
    if (-not $Path) { throw 'Choose an explicit game folder.' }
    if ($Path -match '^[\\/]{2}') { throw 'Use a local folder; network and device paths are not supported.' }
    $full = [IO.Path]::GetFullPath($Path)
    if (([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))).DriveType -eq [IO.DriveType]::Network) { throw 'Network drives are not supported.' }
    Assert-CleanPath $full
    $item = Get-Item -LiteralPath $full -Force
    if (-not $item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') { throw "Not a filesystem folder: $full" }
    if ($full.TrimEnd('\') -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) { throw 'A drive root is not a game folder.' }
    return $item.FullName.TrimEnd('\')
}
function Join-Safe {
    param([string]$Root, [string]$Relative)
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?]' -or $Relative -match '(^|[\\/])\.{1,2}([\\/]|$)') { throw "Unsafe relative path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path -Path $Root -ChildPath $Relative))
    if (-not $full.StartsWith($Root+'\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes selected folder: $Relative" }
    Assert-CleanPath $full
    return $full
}
function Assert-Disjoint {
    param($A, $B)
    if ($A -eq $B -or $A.StartsWith($B+'\',[StringComparison]::OrdinalIgnoreCase) -or $B.StartsWith($A+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Patch extraction and game folders must not overlap.' }
}
function Read-Json { param($Path) Assert-CleanPath $Path; return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
function Assert-Set {
    param($Actual, $Expected, $Label)
    if (@($Actual).Count -ne @($Expected).Count -or @($Actual | Select-Object -Unique).Count -ne @($Expected).Count -or @(Compare-Object @($Actual | Sort-Object) @($Expected | Sort-Object)).Count -ne 0) { throw "Unexpected $Label list." }
}
function Assert-Descriptor {
    param($Value)
    if ($Value.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [Int64]$Value.size -lt 0 -or [string]$Value.size -notmatch '^\d+$') { throw 'Invalid size/SHA-256 descriptor.' }
}
function Read-Manifest {
    param($Path)
    $m = Read-Json $Path
    if ($m.schema_version -ne 1 -or $m.release_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or $m.release_id -match '\.\.') { throw 'Unsupported release manifest.' }
    Assert-Set @($m.targets | ForEach-Object { $_.path }) $script:TargetNames 'target'
    Assert-Set @($m.dependencies | ForEach-Object { $_.path }) $script:DependencyNames 'dependency'
    Assert-Set @($m.installer_files | ForEach-Object { $_.path }) $script:InstallerNames 'installer'
    $support = @($m.support_files | ForEach-Object { $_.path })
    $expectedSupport = @($script:SupportNames)
    if ($null -ne $m.PSObject.Properties['save_migration']) { $expectedSupport += @('SaveMigration.Core.ps1','save-migration-maps.json.gz') }
    # Existing RC1/RC2 receipts may contain their original review-status file.
    if ($support -contains 'REVIEW-STATUS.txt') { $expectedSupport += 'REVIEW-STATUS.txt' }
    if ($support -contains 'SHA256SUMS.txt') { $expectedSupport += 'SHA256SUMS.txt' }
    Assert-Set $support $expectedSupport 'support'
    foreach ($t in $m.targets) {
        Assert-Descriptor $t
        if ($t.payload -cne ('payload/'+$t.path)) { throw 'Unexpected payload path.' }
        $variants = @('original-update2')
        if ($t.path -ceq 'Scarlett.exe') { $variants = @('pristine','menu-fixed') }
        if ($null -ne $m.PSObject.Properties['save_migration']) {
            if ($t.path -ceq 'Scarlett.exe') { $variants += 'english' } else { $variants += @('rc5','rc6','rc7','rc8','test-2026-11-07') }
        }
        Assert-Set @($t.bases | ForEach-Object { $_.variant }) $variants 'base variant'
        foreach ($b in $t.bases) { Assert-Descriptor $b; if ($b.sha256 -eq $t.sha256 -and $b.variant -ne 'english') { throw 'Patched and base hashes must differ.' } }
    }
    foreach ($e in @($m.dependencies)+@($m.support_files)+@($m.installer_files)) { Assert-Descriptor $e }
    return $m
}
function Assert-File {
    param($Path, $Descriptor)
    Assert-CleanPath $Path
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.Length -ne [Int64]$Descriptor.size) { throw "Unexpected file/size: $Path" }
    $hash = Get-Sha $Path
    if ($hash -ne $Descriptor.sha256) { throw "Unknown or changed file: $Path ; observed $hash ; expected $($Descriptor.sha256)" }
}
function Test-File {
    param($Path, $Descriptor)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    Assert-CleanPath $Path
    $i = Get-Item -LiteralPath $Path -Force
    return ($i.Length -eq [Int64]$Descriptor.size -and (Get-Sha $Path) -eq $Descriptor.sha256)
}
function Assert-Closed {
    param($Root)
    Invoke-TestHook 'GameClosedCheck'
    foreach ($p in @(Get-Process -Name Scarlett -ErrorAction SilentlyContinue)) {
        try { $exe = $p.MainModule.FileName } catch { throw 'Cannot verify a Scarlett process path; close it before continuing.' }
        if (-not $exe -or [IO.Path]::GetFullPath($exe) -eq (Join-Safe $Root 'Scarlett.exe')) { throw 'Close Scarlett before installing/restoring. The installer will not stop it.' }
    }
    foreach ($name in $script:TargetNames) {
        $p = Join-Safe $Root $name
        if (((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) { throw "Read-only target: $p" }
        $stream = [IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $stream.Dispose()
    }
}
function Assert-Dependencies {
    param($Root, $Manifest)
    foreach ($e in $Manifest.dependencies) { Assert-File (Join-Safe $Root $e.path) $e }
}
function Assert-Space {
    param($Root, [Int64]$Needed)
    Invoke-TestHook 'SpaceCheck'
    if ((Get-FreeBytes $Root) -lt ($Needed+1048576)) { throw 'Insufficient free space for verified backups, staging and support files.' }
}
function New-Directory {
    param($Path)
    Assert-CleanPath $Path
    [void][IO.Directory]::CreateDirectory($Path)
    Assert-CleanPath $Path
}
function Write-NewBytes {
    param($Path, [byte[]]$Bytes)
    Assert-CleanPath $Path
    $f = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $f.Write($Bytes,0,$Bytes.Length); $f.Flush($true) } finally { $f.Dispose() }
}
function Copy-NewVerified {
    param($Source, $Destination, $Descriptor)
    Assert-File $Source $Descriptor
    Assert-CleanPath $Destination
    $sourceStream = [IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $output = [IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $sourceStream.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
    } finally { $sourceStream.Dispose() }
    Assert-File $Destination $Descriptor
}
function Write-Journal {
    param($Receipt, $Path)
    Assert-CleanPath $Path
    if (Test-Path -LiteralPath $Path) { if ((Get-Sha $Path) -ne $script:JournalHash) { throw 'Journal changed concurrently; recovery evidence retained.' } }
    $temp = Join-Safe ([IO.Path]::GetDirectoryName($Path)) ('journal.'+[Guid]::NewGuid().ToString('N')+'.tmp')
    $json = $Receipt | ConvertTo-Json -Depth 16
    Write-NewBytes $temp ([Text.UTF8Encoding]::new($false).GetBytes($json))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp,$Path,[NullString]::Value,$false) } else { [IO.File]::Move($temp,$Path) }
    $script:JournalHash = Get-Sha $Path
}
function Assert-OwnedRoot {
    param($Root)
    $owner = Join-Safe $Root 'Scarlett-English-Patch/OWNER.txt'
    if (Test-Path -LiteralPath (Join-Safe $Root 'Scarlett-English-Patch')) {
        if (-not (Test-Path -LiteralPath $owner) -or ([IO.File]::ReadAllText($owner)) -cne $script:Owner) { throw 'Existing patch support folder is not recognized; it will not be overwritten.' }
    }
}
function Get-Journals {
    param($Root)
    Assert-OwnedRoot $Root
    $dir = Join-Safe $Root 'Scarlett-English-Patch/backups'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($child in @(Get-ChildItem -LiteralPath $dir -Directory -Force)) {
        Assert-CleanPath $child.FullName
        if ($child.Name -notmatch '^[a-f0-9]{32}$') { continue }
        $file = Join-Safe $child.FullName 'journal.json'
        if (Test-Path -LiteralPath $file) { $r = Read-Json $file; if ($r.owner -cne $script:Owner -or $r.game_root -ine $Root) { throw 'Unrecognized transaction receipt.' }; [pscustomobject]@{Path=$file; Receipt=$r} }
    }
}
function Assert-Receipt {
    param($Root, $ReceiptPath)
    $path = [IO.Path]::GetFullPath($ReceiptPath)
    Assert-CleanPath $path
    $r = Read-Json $path
    if ($r.owner -cne $script:Owner -or $r.schema_version -ne 1 -or $r.game_root -ine $Root -or $r.install_id -notmatch '^[a-f0-9]{32}$') { throw 'Receipt does not belong to the selected game folder.' }
    $transaction = Join-Safe $Root ('Scarlett-English-Patch/backups/'+$r.install_id)
    if ($path -ine (Join-Safe $transaction 'journal.json')) { throw 'Receipt must be the installer-owned journal in the selected game folder.' }
    $manifestPath = Join-Safe $transaction 'release-manifest.json'
    if ((Get-Sha $manifestPath) -ne $r.manifest_sha256) { throw 'Retained manifest hash mismatch.' }
    $m = Read-Manifest $manifestPath
    if ($r.release_id -cne $m.release_id -or $r.state -notin @('preparing','prepared','installing','committed','rolling_back','rolled_back','recovery_required','restoring','restored')) { throw 'Receipt release/state mismatch.' }
    Assert-Set @($r.originals | ForEach-Object { $_.path }) $script:TargetNames 'receipt original'
    foreach ($o in $r.originals) {
        $t = @($m.targets | Where-Object { $_.path -ceq $o.path })[0]
        $match = @($t.bases | Where-Object { $_.variant -ceq $o.variant -and $_.sha256 -eq $o.sha256 -and $_.size -eq $o.size })
        if ($match.Count -ne 1 -or [int]$o.attributes -lt 0 -or (([int]$o.attributes -band 1040) -ne 0)) { throw 'Unrecognized original variant/metadata in receipt.' }
        [void][DateTime]::Parse($o.creation_utc); [void][DateTime]::Parse($o.write_utc)
    }
    $script:JournalHash = Get-Sha $path
    return [pscustomobject]@{Receipt=$r; Manifest=$m; Transaction=$transaction; Path=$path}
}
function Test-OriginalMetadata {
    param($Path, $Original)
    $item=Get-Item -LiteralPath $Path -Force
    return ([int]$item.Attributes -eq [int]$Original.attributes -and $item.CreationTimeUtc.Ticks -eq ([DateTime]::Parse($Original.creation_utc).ToUniversalTime()).Ticks -and $item.LastWriteTimeUtc.Ticks -eq ([DateTime]::Parse($Original.write_utc).ToUniversalTime()).Ticks)
}
function Set-OriginalMetadata {
    param($Path, $Original)
    [IO.File]::SetCreationTimeUtc($Path,[DateTime]::Parse($Original.creation_utc).ToUniversalTime())
    [IO.File]::SetLastWriteTimeUtc($Path,[DateTime]::Parse($Original.write_utc).ToUniversalTime())
    [IO.File]::SetAttributes($Path,[IO.FileAttributes][int]$Original.attributes)
}
function Replace-Known {
    param($Root, $Name, $Staged, $ExpectedCurrent, $ExpectedNew)
    $target = Join-Safe $Root $Name
    Assert-CleanPath $Staged
    Assert-File $Staged $ExpectedNew
    Assert-File $target $ExpectedCurrent
    $probe = [IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $probe.Dispose()
    Assert-CleanPath $target
    Assert-File $target $ExpectedCurrent
    [IO.File]::Replace($Staged,$target,[NullString]::Value,$false)
    Assert-File $target $ExpectedNew
}
function Assert-TemporaryFiles {
    param($Root, $Receipt, $Manifest, [switch]$Remove)
    $expectedNames=@()
    foreach ($t in $Manifest.targets) { foreach ($purpose in @('new','rollback','restore')) { $expectedNames += '.scarlett-english-'+$Receipt.install_id+'-'+$purpose+'-'+$t.path+'.tmp' } }
    Assert-Set @($Receipt.temporary_names) $expectedNames 'receipt temporary file'
    $verified=@()
    foreach ($t in $Manifest.targets) {
        $o=@($Receipt.originals | Where-Object { $_.path -ceq $t.path })[0]
        foreach ($purpose in @('new','rollback','restore')) {
            $name='.scarlett-english-'+$Receipt.install_id+'-'+$purpose+'-'+$t.path+'.tmp'
            $path=Join-Safe $Root $name
            if (Test-Path -LiteralPath $path) {
                $descriptor=$o; if ($purpose -eq 'new') { $descriptor=$t }
                Assert-File $path $descriptor; $verified += [pscustomobject]@{Path=$path; Descriptor=$descriptor}
            }
        }
    }
    if ($Remove) { foreach ($entry in $verified) { Assert-CleanPath $entry.Path; Assert-File $entry.Path $entry.Descriptor; Remove-Item -LiteralPath $entry.Path -Force } }
}
function Select-GameFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description='Select the separate Scarlett game folder to install or restore.'
    $dialog.ShowNewFolderButton=$false
    try { if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath } }
    finally { $dialog.Dispose() }
    return $null
}
function Select-Receipt {
    param($GamePath)
    $root=Get-Root $GamePath
    $eligible=@()
    foreach ($j in @(Get-Journals $root)) {
        $ctx=Assert-Receipt $root $j.Path
        if ($ctx.Receipt.state -in @('committed','preparing','prepared','installing','rolling_back','recovery_required','restoring')) { $eligible += $ctx }
    }
    if ($eligible.Count -eq 0) { Write-Host 'No installed or pending patch receipt was found.'; return $null }
    if ($eligible.Count -eq 1) { return $eligible[0].Path }
    Write-Host 'Choose the installation to restore (0 cancels):'
    for ($i=0;$i -lt $eligible.Count;$i++) { Write-Host (($i+1).ToString()+': '+$eligible[$i].Receipt.release_id+' - '+$eligible[$i].Receipt.state+' - '+$eligible[$i].Receipt.install_id) }
    $answer=Read-Host 'Number'; $number=0
    if (-not [int]::TryParse($answer,[ref]$number) -or $number -lt 0 -or $number -gt $eligible.Count) { throw 'Invalid selection; no files changed.' }
    if ($number -eq 0) { return $null }
    return $eligible[$number-1].Path
}
function Install-Support {
    param($Root, $Package, $Manifest, $ManifestPath, [switch]$ValidateOnly)
    $release = Join-Safe $Root ('Scarlett-English-Patch/releases/'+$Manifest.release_id)
    $all = @($Manifest.support_files)+@($Manifest.installer_files)
    $digest=Get-Sha $ManifestPath
    $descriptor = [pscustomobject]@{size=(Get-Item -LiteralPath $ManifestPath).Length;sha256=$digest}
    $marker=Join-Safe $release '_INSTALLER-MANIFEST.sha256'
    if (Test-Path -LiteralPath $release) {
        if (-not (Test-Path -LiteralPath $marker) -or ([IO.File]::ReadAllText($marker)) -cne $digest) { throw 'Existing release support is not owned by this exact manifest.' }
        $matching=@(Get-Journals $Root | Where-Object { $_.Receipt.release_id -ceq $Manifest.release_id -and $_.Receipt.manifest_sha256 -eq $digest })
        if ($matching.Count -eq 0) { throw 'No matching transaction owns the existing release support.' }
        foreach ($e in $all) { $dst=Join-Safe $release $e.path; if (Test-Path -LiteralPath $dst) { Assert-File $dst $e } }
        $retained=Join-Safe $release 'release-manifest.json'
        if (Test-Path -LiteralPath $retained) { Assert-File $retained $descriptor }
    }
    if ($ValidateOnly) { return }
    if (-not (Test-Path -LiteralPath $release)) { New-Directory $release; Write-NewBytes $marker ([Text.Encoding]::ASCII.GetBytes($digest)) }
    $n=0
    foreach ($e in $all) {
        $dst=Join-Safe $release $e.path
        if (-not (Test-Path -LiteralPath $dst)) { New-Directory ([IO.Path]::GetDirectoryName($dst)); Copy-NewVerified (Join-Safe $Package $e.path) $dst $e }
        Assert-File $dst $e; $n++; Invoke-TestHook ('AfterSupportFile'+$n)
    }
    $retained=Join-Safe $release 'release-manifest.json'
    if (-not (Test-Path -LiteralPath $retained)) { Copy-NewVerified $ManifestPath $retained $descriptor }
    Assert-File $retained $descriptor
}
function Invoke-PatchInstall {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$GamePath, [string]$PackageRoot, [string]$SaveSourceRelease, [string]$SaveDictionary)
    $root = Get-Root $GamePath; $package = Get-Root $PackageRoot
    Assert-Disjoint $root $package
    $manifestPath = Join-Safe $package 'release-manifest.json'; $m = Read-Manifest $manifestPath
    foreach ($e in $m.targets) { Assert-File (Join-Safe $package $e.payload) $e }
    foreach ($e in @($m.support_files)+@($m.installer_files)) { Assert-File (Join-Safe $package $e.path) $e }
    Assert-Dependencies $root $m; Assert-Closed $root
    Install-Support $root $package $m $manifestPath -ValidateOnly
    $journals = @(Get-Journals $root)
    foreach ($j in $journals) { if ($j.Receipt.state -notin @('committed','restored','rolled_back')) { throw "Pending transaction: run Restore.cmd with receipt $($j.Path)" } }
    $allFinal = @($m.targets | Where-Object { -not (Test-File (Join-Safe $root $_.path) $_) }).Count -eq 0
    if ($allFinal) {
        foreach ($j in $journals) {
            if ($j.Receipt.state -eq 'committed' -and $j.Receipt.release_id -ceq $m.release_id -and $j.Receipt.manifest_sha256 -eq (Get-Sha $manifestPath)) {
                $ctx = Assert-Receipt $root $j.Path
                foreach ($o in $ctx.Receipt.originals) { Assert-File (Join-Safe $ctx.Transaction $o.path) $o }
                $release = Join-Safe $root ('Scarlett-English-Patch/releases/'+$m.release_id)
                foreach ($e in @($m.support_files)+@($m.installer_files)) { Assert-File (Join-Safe $release $e.path) $e }
                Assert-File (Join-Safe $release 'release-manifest.json') ([pscustomobject]@{size=(Get-Item -LiteralPath $manifestPath).Length;sha256=(Get-Sha $manifestPath)})
                Assert-TemporaryFiles $root $ctx.Receipt $m
                Write-Output 'Patch files already installed and verified. Saves were not converted again. No files changed.'; return
            }
        }
        throw 'Patched files have no matching verified committed receipt.'
    }
    $originals = @()
    foreach ($t in $m.targets) {
        $path = Join-Safe $root $t.path; $item = Get-Item -LiteralPath $path -Force
        $hash = Get-Sha $path
        $matches = @($t.bases | Where-Object { $_.sha256 -eq $hash -and $_.size -eq $item.Length })
        if ($matches.Count -ne 1) { throw "Unknown/newer or mixed target refused: $path ; observed $hash" }
        $originals += [pscustomobject]@{path=$t.path;variant=$matches[0].variant;size=$item.Length;sha256=$hash;attributes=[int]$item.Attributes;creation_utc=$item.CreationTimeUtc.ToString('o');write_utc=$item.LastWriteTimeUtc.ToString('o')}
    }
    $needed = [Int64]0
    foreach ($e in @($m.targets)+$originals+@($m.support_files)+@($m.installer_files)) { $needed += [Int64]$e.size }
    Assert-Space $root $needed
    $id = New-InstallId
    if ($id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid generated install ID.' }
    $tx = Join-Safe $root ('Scarlett-English-Patch/backups/'+$id)
    if (Test-Path -LiteralPath $tx) { throw 'Backup directory collision; nothing overwritten.' }
    if (-not $PSCmdlet.ShouldProcess($root, 'Install two verified files; keep exact backups and release notices')) { return }
    $supportRoot = Join-Safe $root 'Scarlett-English-Patch'
    if (-not (Test-Path -LiteralPath $supportRoot)) { New-Directory $supportRoot; Write-NewBytes (Join-Safe $supportRoot 'OWNER.txt') ([Text.Encoding]::UTF8.GetBytes($script:Owner)) }
    New-Directory $tx
    $manifestDesc = [pscustomobject]@{size=(Get-Item -LiteralPath $manifestPath).Length;sha256=(Get-Sha $manifestPath)}
    Copy-NewVerified $manifestPath (Join-Safe $tx 'release-manifest.json') $manifestDesc
    $receipt = [pscustomobject]@{owner=$script:Owner;schema_version=1;install_id=$id;release_id=$m.release_id;game_root=$root;manifest_sha256=$manifestDesc.sha256;state='preparing';originals=$originals;replaced=@();temporary_names=@($m.targets | ForEach-Object { $targetName=$_.path; foreach ($purpose in @('new','rollback','restore')) { '.scarlett-english-'+$id+'-'+$purpose+'-'+$targetName+'.tmp' } });save_migration=$null;recovery_note=''}
    $journal = Join-Safe $tx 'journal.json'; $script:JournalHash=$null; Write-Journal $receipt $journal
    $savePlan=$null
    try {
        $n=0
        foreach ($o in $originals) { Copy-NewVerified (Join-Safe $root $o.path) (Join-Safe $tx $o.path) $o; $n++; Invoke-TestHook ('AfterBackup'+$n) }
        foreach ($t in $m.targets) { Copy-NewVerified (Join-Safe $package $t.payload) (Join-Safe $root ('.scarlett-english-'+$id+'-new-'+$t.path+'.tmp')) $t }
        Install-Support $root $package $m $manifestPath
        foreach ($o in $originals) { Assert-File (Join-Safe $tx $o.path) $o }
        foreach ($t in $m.targets) { Assert-File (Join-Safe $root ('.scarlett-english-'+$id+'-new-'+$t.path+'.tmp')) $t }
        $savePlan=Prepare-InstallerSaveMigration $root $package $m $tx $receipt $journal $SaveSourceRelease $SaveDictionary
        $receipt.state='prepared'; Write-Journal $receipt $journal; Invoke-TestHook 'BeforeReplace'
        Assert-Closed $root
        $n=0
        foreach ($t in $m.targets) {
            $o=@($originals | Where-Object { $_.path -ceq $t.path })[0]
            Replace-Known $root $t.path (Join-Safe $root ('.scarlett-english-'+$id+'-new-'+$t.path+'.tmp')) $o $t
            $receipt.replaced += $t.path; $receipt.state='installing'; Write-Journal $receipt $journal
            $n++; Invoke-TestHook ('AfterReplace'+$n)
        }
        Assert-Dependencies $root $m
        foreach ($t in $m.targets) { Assert-File (Join-Safe $root $t.path) $t }
        Assert-TemporaryFiles $root $receipt $m -Remove
        Publish-InstallerSaveMigration $root $tx $receipt $journal $savePlan
        $receipt.state='committed'; Write-Journal $receipt $journal
        Write-Output ('Installed. Exact pre-install files and receipt: '+$journal)
    } catch {
        $cause=$_.Exception.Message; $receipt.state='rolling_back'
        try { Write-Journal $receipt $journal } catch { }
        $safe=$true
        try { Undo-InstallerSaveMigration $root $tx $receipt $journal } catch { $safe=$false; $receipt.recovery_note=$_.Exception.Message }
        foreach ($t in @($m.targets)[1,0]) {
            $o=@($originals | Where-Object { $_.path -ceq $t.path })[0]; $path=Join-Safe $root $t.path
            try {
                if (Test-File $path $o) { continue }
                if (-not (Test-File $path $t)) { throw 'Current target is unknown; it was not overwritten during rollback.' }
                Assert-File (Join-Safe $tx $o.path) $o
                $temp=Join-Safe $root ('.scarlett-english-'+$id+'-rollback-'+$o.path+'.tmp')
                Copy-NewVerified (Join-Safe $tx $o.path) $temp $o
                Replace-Known $root $o.path $temp $t $o; Set-OriginalMetadata $path $o
            } catch { $safe=$false; $receipt.recovery_note=$_.Exception.Message }
        }
        if ($safe) { try { Assert-TemporaryFiles $root $receipt $m -Remove } catch { $safe=$false; $receipt.recovery_note=$_.Exception.Message } }
        if ($safe) { $receipt.state='rolled_back' } else { $receipt.state='recovery_required' }
        try { Write-Journal $receipt $journal } catch { }
        throw "Install failed: $cause ; transaction $journal ; state $($receipt.state). Backups/evidence retained."
    } finally { Close-InstallerSaveHandles $savePlan }
}
function Invoke-PatchRestore {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$GamePath, [string]$ReceiptPath)
    $root=Get-Root $GamePath; Assert-OwnedRoot $root
    $ctx=Assert-Receipt $root $ReceiptPath; $r=$ctx.Receipt; $m=$ctx.Manifest
    Assert-InstallerSaveRestore $root $ctx.Transaction $r
    Assert-Dependencies $root $m; Assert-Closed $root
    $allBase=$true
    foreach ($t in $m.targets) {
        $o=@($r.originals | Where-Object { $_.path -ceq $t.path })[0]; $path=Join-Safe $root $t.path
        if (Test-File $path $o) { continue }
        $allBase=$false
        if (-not (Test-File $path $t)) { throw "Unknown/newer current target refused: $path" }
    }
    if ($allBase) {
        $metadataExact=$true
        foreach ($o in $r.originals) {
            $backup=Join-Safe $ctx.Transaction $o.path
            if (Test-Path -LiteralPath $backup) { Assert-File $backup $o }
            if (-not (Test-OriginalMetadata (Join-Safe $root $o.path) $o)) { $metadataExact=$false }
        }
        Assert-TemporaryFiles $root $r $m
        if ($metadataExact -and $r.state -in @('restored','rolled_back') -and ((Get-SaveMigrationReceipt $r) -eq $null -or (Get-SaveMigrationReceipt $r).state -in @('restored','rolled_back'))) { Write-Output 'Original files already present. No files changed.'; return }
        if (-not $PSCmdlet.ShouldProcess($root, 'Verify already-original files, restore recorded metadata and close pending transaction')) { return }
        foreach ($o in $r.originals) { Set-OriginalMetadata (Join-Safe $root $o.path) $o }
        Assert-TemporaryFiles $root $r $m -Remove
        Restore-InstallerSaveMigration $root $ctx.Transaction $r $ctx.Path
        $r.state='restored'; Write-Journal $r $ctx.Path
        Write-Output 'Original files verified; pending transaction closed. Backups/evidence retained.'
        return
    }
    foreach ($o in $r.originals) { Assert-File (Join-Safe $ctx.Transaction $o.path) $o }
    Assert-TemporaryFiles $root $r $m
    $needed=[Int64]0; foreach ($o in $r.originals) { $needed += [Int64]$o.size }; Assert-Space $root $needed
    if (-not $PSCmdlet.ShouldProcess($root, 'Restore original game and pre-install save profile; preserve newer saves in the backup')) { return }
    $r.state='restoring'; Write-Journal $r $ctx.Path
    try {
        foreach ($o in $r.originals) {
            $temp=Join-Safe $root ('.scarlett-english-'+$r.install_id+'-restore-'+$o.path+'.tmp')
            if (Test-Path -LiteralPath $temp) { Assert-File $temp $o } else { Copy-NewVerified (Join-Safe $ctx.Transaction $o.path) $temp $o }
        }
        Assert-Closed $root
        $n=0
        foreach ($t in $m.targets) {
            $o=@($r.originals | Where-Object { $_.path -ceq $t.path })[0]; $target=Join-Safe $root $t.path
            if (-not (Test-File $target $o)) { Replace-Known $root $t.path (Join-Safe $root ('.scarlett-english-'+$r.install_id+'-restore-'+$o.path+'.tmp')) $t $o }
            Set-OriginalMetadata $target $o; Assert-File $target $o
            $n++; Invoke-TestHook ('RestoreAfterReplace'+$n)
        }
        Assert-Dependencies $root $m
        Assert-TemporaryFiles $root $r $m -Remove
        Restore-InstallerSaveMigration $root $ctx.Transaction $r $ctx.Path
        $r.state='restored'; Write-Journal $r $ctx.Path
        Write-Output ('Restored exact pre-install variants. Backups/notices retained: '+$ctx.Transaction)
    } catch {
        $r.recovery_note=$_.Exception.Message
        try { Write-Journal $r $ctx.Path } catch { }
        throw "Restore interrupted; rerun with the same receipt after resolving the error. Known backups retained: $($ctx.Path)"
    }
}
