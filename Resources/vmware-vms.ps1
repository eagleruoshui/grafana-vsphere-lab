#requires -Version 3

# Pull in vars
$vars = (Get-Item $PSScriptRoot).Parent.FullName + '\vars.ps1'
Invoke-Expression -Command ($vars)

### Import modules or snapins
$powercli = Get-PSSnapin -Name VMware.VimAutomation.Core -Registered

try 
{
    switch ($powercli.Version.Major) {
        {
            $_ -ge 6
        }
        {
            Import-Module -Name VMware.VimAutomation.Core -ErrorAction Stop
            Write-Host -Object 'PowerCLI 6+ module imported'
        }
        5
        {
            Add-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction Stop
            Write-Warning -Message 'PowerCLI 5 snapin added; recommend upgrading your PowerCLI version'
        }
        default 
        {
            throw 'This script requires PowerCLI version 5 or later'
        }
    }
}
catch 
{
    throw 'Could not load the required VMware.VimAutomation.Vds cmdlets'
}

# Ignore self-signed SSL certificates for vCenter Server (optional)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DisplayDeprecationWarnings:$false -Scope User -Confirm:$false

# Connect to vCenter
try 
{
    $null = Connect-VIServer $global:vc -ErrorAction Stop
}
catch 
{
    throw 'Could not connect to vCenter'
}

# Collect VM Status
$vmstate = @{}
(Get-VM |
Get-View).Runtime.PowerState | Group-Object | ForEach-Object -Process {
    if ($_.Name -eq 'poweredOn') 
    {
        $vmstate.Add('vmon',$_.Count)
    }
    else 
    {
        $vmstate.Add('vmoff',$_.Count)
    }
}

# Store in the points variable
[System.Collections.ArrayList]$points = @()
$points.Add($vmstate.vmon)
$points.Add($vmstate.vmoff)

# Wrap the points into a null array to meet InfluxDB json requirements. Sad panda.
[System.Collections.ArrayList]$nullarray = @()
$nullarray.Add($points)

# Build the post body
$body = @{}
$body.Add('name','vm_state')
$body.Add('columns',@('On', 'Off'))
$body.Add('points',$nullarray)

# Convert to json
$finalbody = $body | ConvertTo-Json

# Post to API
try 
{
    $r = Invoke-WebRequest -Uri $global:url -Body ('['+$finalbody+']') -ContentType 'application/json' -Method Post -ErrorAction:Stop
    Write-Host -Object "Data has been posted, status is $($r.StatusCode) $($r.StatusDescription)"        
}
catch 
{
    throw 'Could not POST to InfluxDB API endpoint'
}

# Disconnect
Disconnect-VIServer -Confirm:$false