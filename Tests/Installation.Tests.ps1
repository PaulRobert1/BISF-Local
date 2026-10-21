BeforeDiscovery {
    $root=Split-Path $PSScriptRoot -Parent
    if (Test-Path "$root/Modules/BISF.Installation.psm1") { Import-Module "$root/Modules/BISF.Installation.psm1" -Force -Global }
}
Describe 'Automatic installation ACL policy' {
    It 'provides the automatic installation initializer' {
        Get-Command Initialize-BISFInstallation -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
Describe 'Installation trust and data boundaries' {
    InModuleScope BISF.Installation {
        BeforeAll {
            function New-TestSnapshot([string]$Owner='S-1-5-32-544',[string]$Sid='S-1-5-32-545',[int]$Rights=131241,[bool]$InheritOnly=$false) {
                [pscustomobject]@{Owner=$Owner;Rules=@([pscustomobject]@{Sid=$Sid;Rights=$Rights;Allow=$true;InheritOnly=$InheritOnly});Sddl='original'}
            }
        }
        It 'accepts Users RX but rejects each dangerous target right' {
            Test-BISFInstallationAclSafe (New-TestSnapshot) | Should -BeTrue
            foreach ($bit in @(2,4,16,64,256,65536,262144,524288)) {
                Test-BISFInstallationAclSafe (New-TestSnapshot -Rights $bit) | Should -BeFalse
            }
        }
        It 'requires private runtime data even when code policy accepts read grants' {
            Test-BISFInstallationAclSafe (New-TestSnapshot) -Private | Should -BeFalse
            Test-BISFInstallationAclSafe (New-TestSnapshot -Sid 'S-1-5-18' -Rights 2032127) -Private | Should -BeTrue
        }
        It 'distinguishes inherited-only grants and ancestor create rights' {
            Test-BISFInstallationAclSafe (New-TestSnapshot -Rights 2032127 -InheritOnly $true) | Should -BeTrue
            Test-BISFInstallationAclSafe (New-TestSnapshot -Rights 4) -Ancestor | Should -BeTrue
            Test-BISFInstallationAclSafe (New-TestSnapshot -Rights 64) -Ancestor | Should -BeFalse
        }
        It 'rejects untrusted owners and generic write grants' {
            Test-BISFInstallationAclSafe (New-TestSnapshot -Owner 'S-1-5-21-1') | Should -BeFalse
            Test-BISFInstallationAclSafe (New-TestSnapshot -Rights 1073741824) | Should -BeFalse
        }
        It 'matches directory boundaries without accepting sibling prefixes' {
            Test-BISFInstallationWithin '/test/app/state/a' '/test/app/state' | Should -BeTrue
            Test-BISFInstallationWithin '/test/app/stately/a' '/test/app/state' | Should -BeFalse
        }
        It 'fails a reparse point before an ACL write' {
            Mock Get-Item { [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint;PSIsContainer=$true;FullName='/test/link'} }
            { Assert-BISFInstallationObject '/test/link' } | Should -Throw '*reparse*'
        }
        It 'fails multiply linked files before an ACL write' {
            Mock Get-Item { [pscustomobject]@{Attributes=[IO.FileAttributes]::Normal;PSIsContainer=$false;FullName='/test/code'} }
            Mock Get-BISFInstallationLinkCount { 2 }
            { Assert-BISFInstallationObject '/test/code' } | Should -Throw '*hard link*'
        }
    }
}
Describe 'Installation initialization decisions' {
    InModuleScope BISF.Installation {
        BeforeEach {
            $script:package=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null=New-Item -ItemType Directory -Path $script:package
            $null=New-Item -ItemType Directory -Path (Join-Path $script:package 'state')
            $null=New-Item -ItemType Directory -Path (Join-Path $script:package 'logs')
            $script:config=Join-Path $script:package 'GlobalConfig.xml'
            [IO.File]::WriteAllText($script:config,'<BISF><Logging><Path>./logs</Path></Logging></BISF>')
            [IO.File]::WriteAllText((Join-Path $script:package 'state/Prepare.pending'),'Retain this marker')
            Mock Get-BISFInstallationLinkCount { 1 }
            Mock Assert-BISFInstallationAncestors {}
            $script:unsafe=$false
            $script:repaired=New-Object 'Collections.Generic.List[string]'
            $script:backups=@()
            Mock Get-BISFInstallationAcl {
                param($Path)
                $code= -not ((Test-BISFInstallationWithin $Path (Join-Path $script:package 'state')) -or (Test-BISFInstallationWithin $Path (Join-Path $script:package 'logs')))
                $rights=if($script:unsafe -and $code -and $Path -notin $script:repaired) { 278 } else {131241}
                $rules=if($code) { @([pscustomobject]@{Sid='S-1-5-32-545';Rights=$rights;Allow=$true;InheritOnly=$false}) } else { @() }
                [pscustomobject]@{Owner='S-1-5-32-544';Protected=$true;Sddl='O:BAD:P';Rules=$rules}
            }
            Mock New-BISFInstallationBackup {
                param($ScriptRoot,$Snapshots)
                $script:backups=@($Snapshots)
                Join-Path $ScriptRoot 'fake-protected-backup.json'
            }
            Mock Set-BISFInstallationAcl { param($Path,$Directory,$Private); $script:repaired.Add($Path) }
        }
        It 'preserves already safe installation descriptors and pending marker contents' {
            Protect-BISFInstallationTree $script:package $script:config
            $script:backups.Count | Should -Be 0
            $script:repaired.Count | Should -Be 0
            [IO.File]::ReadAllText((Join-Path $script:package 'state/Prepare.pending')) | Should -BeExactly 'Retain this marker'
        }
        It 'backs up all original descriptors before correcting unsafe code' {
            $script:unsafe=$true
            Protect-BISFInstallationTree $script:package $script:config
            $script:backups.Count | Should -Be 5
            $script:repaired.Count | Should -Be 2
            $script:backups.Path | Should -Contain $script:config
            [IO.File]::ReadAllText((Join-Path $script:package 'state/Prepare.pending')) | Should -BeExactly 'Retain this marker'
        }
        It 'precreates a missing log directory privately without touching pending data' {
            Remove-Item -LiteralPath (Join-Path $script:package 'logs')
            Mock New-BISFInstallationPrivateDirectory { param($Path); $null=New-Item -ItemType Directory -Path $Path }
            Protect-BISFInstallationTree $script:package $script:config
            Test-Path -LiteralPath (Join-Path $script:package 'logs') -PathType Container | Should -BeTrue
            $script:backups.Count | Should -Be 4
            [IO.File]::ReadAllText((Join-Path $script:package 'state/Prepare.pending')) | Should -BeExactly 'Retain this marker'
        }
        It 'refuses an existing operator seal without changing permissions' {
            [IO.File]::WriteAllText((Join-Path $script:package 'state/operator-seal.json'),'retained')
            $script:unsafe=$true
            { Protect-BISFInstallationTree $script:package $script:config } | Should -Throw '*operator-seal state*'
            $script:backups.Count | Should -Be 0
            $script:repaired.Count | Should -Be 0
        }
        It 'never hardens anything if the original descriptor backup fails' {
            $script:unsafe=$true
            Mock New-BISFInstallationBackup { throw 'Backup unavailable' }
            { Protect-BISFInstallationTree $script:package $script:config } | Should -Throw '*Backup unavailable*'
            $script:repaired.Count | Should -Be 0
        }
        It 'validates all hard links before backup or mutation' {
            $script:unsafe=$true
            Mock Get-BISFInstallationLinkCount { param($Path); if($Path -eq $script:config) {2} else {1} }
            { Protect-BISFInstallationTree $script:package $script:config } | Should -Throw '*hard link*'
            $script:backups.Count | Should -Be 0
            $script:repaired.Count | Should -Be 0
        }
        It 'fails closed when an ACL write does not establish the intended protection' {
            $script:unsafe=$true
            Mock Set-BISFInstallationAcl {}
            { Protect-BISFInstallationTree $script:package $script:config } | Should -Throw '*permissions remain unsafe*'
        }
        It 'refuses log paths that overlap installation code' {
            [IO.File]::WriteAllText($script:config,'<BISF><Logging><Path>./Modules</Path></Logging></BISF>')
            { Protect-BISFInstallationTree $script:package $script:config } | Should -Throw '*overlaps*'
            $script:repaired.Count | Should -Be 0
        }
        It 'does not include configured external logs in the mutation scope' {
            $outside=Join-Path $TestDrive 'external-logs'
            [IO.File]::WriteAllText($script:config,('<BISF><Logging><Path>{0}</Path></Logging></BISF>' -f $outside))
            @(Get-BISFInstallationPrivateRoots $script:package $script:config) | Should -Not -Contain $outside
        }
    }
}
Describe 'Required access and protected backup' {
    InModuleScope BISF.Installation {
        It 'rejects a null DACL on ancestors instead of trusting an empty rule list' {
            $acl=[pscustomobject]@{Owner='S-1-5-32-544';NullDacl=$true;Rules=@()}
            Test-BISFInstallationAclSafe $acl -Ancestor | Should -BeFalse
        }
        It 'repairs code that cannot be read by normal users' {
            $acl=[pscustomobject]@{Owner='S-1-5-32-544';Protected=$true;Rules=@()}
            Test-BISFInstallationAclSafe $acl -Code | Should -BeFalse
        }
        It 'repairs code with a deny that blocks Explorer read access' {
            $acl=[pscustomobject]@{Owner='S-1-5-32-544';Protected=$true;Rules=@(
                [pscustomobject]@{Sid='S-1-5-32-545';Rights=131241;Allow=$true;InheritOnly=$false},
                [pscustomobject]@{Sid='S-1-1-0';Rights=1;Allow=$false;InheritOnly=$false}
            )}
            Test-BISFInstallationAclSafe $acl -Code | Should -BeFalse
        }
        It 'protects the newly written backup file before checking its final descriptor' {
            $script:backupProtected=$false
            Mock New-BISFInstallationPrivateDirectory { param($Path); $null=New-Item -ItemType Directory -Path $Path }
            Mock Get-BISFInstallationLinkCount { 1 }
            Mock Get-BISFInstallationAcl {
                param($Path)
                [pscustomobject]@{Owner='S-1-5-32-544';Protected=($Path -notlike '*.json' -or $script:backupProtected);Rules=@()}
            }
            Mock Set-BISFInstallationAcl { param($Path,$Directory,$Private); if(-not $Directory -and $Private) {$script:backupProtected=$true} }
            $p=New-BISFInstallationBackup $TestDrive @([pscustomobject]@{Path='original';Sddl='original-acl'})
            $script:backupProtected | Should -BeTrue
            (Get-Content $p -Raw | ConvertFrom-Json).Sddl | Should -Be 'original-acl'
        }
    }
}
