#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Checkbox UI for optional BISF-Local master-image log cleanup.
.DESCRIPTION
  Only edits GlobalConfig.xml after explicit Save. Never deletes logs,
  runs BIS-F Prepare, or requests shutdown.
#>
[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $PSScriptRoot 'GlobalConfig.xml'))
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
    throw 'Use elevated 64-bit Windows PowerShell 5.1.'
}
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
[System.Windows.Forms.Application]::EnableVisualStyles()
$ConfigPath=[IO.Path]::GetFullPath($ConfigPath)
$SchemaPath=Join-Path $PSScriptRoot 'GlobalConfig.xsd'
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    throw 'GlobalConfig.xml and GlobalConfig.xsd must exist in this BISF package.'
}
$doc=New-Object Xml.XmlDocument
$doc.XmlResolver=$null
$settings=New-Object Xml.XmlReaderSettings
$settings.XmlResolver=$null
$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
$reader=[Xml.XmlReader]::Create($ConfigPath,$settings)
try { $doc.Load($reader) } finally { $reader.Dispose() }
if ($null -eq $doc.SelectSingleNode('/BISF/FinalAction')) { throw 'Invalid BISF GlobalConfig.xml.' }
$ev=$false; $own=$false
$a=$doc.SelectSingleNode('/BISF/LogCleanup/WindowsEventLogs')
$b=$doc.SelectSingleNode('/BISF/LogCleanup/BISFLogs')
if ($null -ne $a) { $ev=[Xml.XmlConvert]::ToBoolean(([string]$a.InnerText).Trim()) }
if ($null -ne $b) { $own=[Xml.XmlConvert]::ToBoolean(([string]$b.InnerText).Trim()) }
$action=[string]$doc.SelectSingleNode('/BISF/FinalAction').InnerText

$form=New-Object System.Windows.Forms.Form
$form.Text='BISF-Local - Log cleanup options'
$form.StartPosition='CenterScreen'
$form.ClientSize=New-Object System.Drawing.Size(610,255)
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false
$form.MinimizeBox=$false

$title=New-Object System.Windows.Forms.Label
$title.Location=New-Object System.Drawing.Point(20,12)
$title.Size=New-Object System.Drawing.Size(565,35)
$title.Font=New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
$title.Text='Master-image log cleanup (explicit opt-in)'
$form.Controls.Add($title)

$eventCheck=New-Object System.Windows.Forms.CheckBox
$eventCheck.Location=New-Object System.Drawing.Point(23,55)
$eventCheck.Size=New-Object System.Drawing.Size(560,27)
$eventCheck.Text='Clear Windows Event Logs: Application, System, Setup'
$eventCheck.Checked=$ev
$form.Controls.Add($eventCheck)

$ownCheck=New-Object System.Windows.Forms.CheckBox
$ownCheck.Location=New-Object System.Drawing.Point(23,89)
$ownCheck.Size=New-Object System.Drawing.Size(560,27)
$ownCheck.Text='Remove only BISF-Local generated diagnostic log files'
$ownCheck.Checked=$own
$form.Controls.Add($ownCheck)

$description=New-Object System.Windows.Forms.Label
$description.Location=New-Object System.Drawing.Point(23,120)
$description.Size=New-Object System.Drawing.Size(570,48)
$description.Text=('Security audit logs, Citrix/WEM/FSLogix logs and remote logs remain intact.' + [Environment]::NewLine + 'Save changes XML only; no cleanup or shutdown is started.')
$form.Controls.Add($description)

$status=New-Object System.Windows.Forms.Label
$status.Location=New-Object System.Drawing.Point(23,181)
$status.Size=New-Object System.Drawing.Size(370,36)
$status.Text="Current FinalAction: $action"
$form.Controls.Add($status)

$save=New-Object System.Windows.Forms.Button
$save.Location=New-Object System.Drawing.Point(414,181)
$save.Size=New-Object System.Drawing.Size(90,31)
$save.Text='Save XML'
$form.Controls.Add($save)

$cancel=New-Object System.Windows.Forms.Button
$cancel.Location=New-Object System.Drawing.Point(511,181)
$cancel.Size=New-Object System.Drawing.Size(80,31)
$cancel.Text='Cancel'
$cancel.Add_Click({ $form.Close() })
$form.Controls.Add($cancel)

$save.Add_Click({
    try {
        if (($eventCheck.Checked -or $ownCheck.Checked) -and $action -ne 'Shutdown') {
            [void][System.Windows.Forms.MessageBox]::Show(
                'Set FinalAction=Shutdown in GlobalConfig.xml first. Saving cannot silently enable shutdown.',
                'Log cleanup requires an explicit shutdown plan',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $node=$doc.SelectSingleNode('/BISF/LogCleanup')
        if ($null -eq $node) {
            $node=$doc.CreateElement('LogCleanup')
            $cm=$doc.SelectSingleNode('/BISF/ConfigurationManager')
            if ($null -eq $cm) { throw 'Cannot locate ConfigurationManager for safe XML insertion.' }
            $null=$doc.DocumentElement.InsertBefore($node,$cm)
        }
        foreach ($name in @('WindowsEventLogs','BISFLogs')) {
            $child=$node.SelectSingleNode($name)
            if ($null -eq $child) {
                $child=$doc.CreateElement($name)
                $null=$node.AppendChild($child)
            }
            if ($name -eq 'WindowsEventLogs') {
                $child.InnerText=([string]$eventCheck.Checked).ToLowerInvariant()
            } else {
                $child.InnerText=([string]$ownCheck.Checked).ToLowerInvariant()
            }
        }
        $schemas=New-Object System.Xml.Schema.XmlSchemaSet
        $null=$schemas.Add($null,$SchemaPath)
        $doc.Schemas=$schemas
        $handler=[System.Xml.Schema.ValidationEventHandler]{
            param($sender,$event)
            throw $event.Exception
        }
        $doc.Validate($handler)
        $doc.Save($ConfigPath)
        [void][System.Windows.Forms.MessageBox]::Show(
            ('Saved XML to ' + $ConfigPath + [Environment]::NewLine + 'No logs were cleared or shutdown requested.'),
            'Options saved',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, 'Save failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
[void]$form.ShowDialog()
$form.Dispose()
