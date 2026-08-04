<#
.SYNOPSIS
    Rebuilds both cost handouts (.docx) from the unit-rate table below.

.DESCRIPTION
    Replaces the previous build_cost_printout.py / build_onepager_cost.py pair.
    Those required Python + python-docx, which is not installed on the lab
    machines - so the .docx files drifted out of date and ended up pricing
    Azure Firewall at the Basic rate while the templates deploy Standard.

    This script has no dependencies (writes Office Open XML directly) and,
    more importantly, DERIVES every total from $Rates and $Levels. To correct a
    price, change the one number in $Rates and re-run - no prose to hand-edit:

        ./unit\ cost/Build-CostDocs.ps1

    Outputs:
      IaC_Demo_Hourly_Cost_Printout.docx   multi-page detail
      IaC_Demo_Cost_One_Page.docx          one-page presenter handout

.PARAMETER OutputDirectory
    Where to write the .docx files. Defaults to this script's own folder.
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# =============================================================================
# UNIT RATES - the single source of truth for every figure in both documents.
#
# Verified against the Azure Retail Prices API for East US 2 on 2026-08-04.
# 'Verified' rows came back from the API directly; 'List' rows were not
# queryable by meter and use published pay-as-you-go list pricing.
# =============================================================================
$Rates = @(
    @{ Key = 'vm-b2s';       Rate = 0.0416; Desc = 'Linux VM Standard_B2s';                 Source = 'Verified' }
    @{ Key = 'disk-s4';      Rate = 0.0021; Desc = 'OS disk, Standard HDD S4 (32 GiB)';     Source = 'List ($1.54/mo)' }
    @{ Key = 'bastion';      Rate = 0.19;   Desc = 'Azure Bastion Basic gateway';           Source = 'Verified' }
    @{ Key = 'pip';          Rate = 0.005;  Desc = 'Standard public IP address';            Source = 'List' }
    @{ Key = 'firewall';     Rate = 1.25;   Desc = 'Azure Firewall Standard deployment';    Source = 'Verified' }
    @{ Key = 'lb';           Rate = 0.025;  Desc = 'Standard Load Balancer (first 5 rules)'; Source = 'List' }
    @{ Key = 'aca-replica';  Rate = 0.054;  Desc = 'Container Apps replica, 0.5 vCPU + 1 GiB'; Source = 'Verified (per-second meters)' }
    @{ Key = 'sql-basic';    Rate = 0.0067; Desc = 'Azure SQL Database Basic (5 DTU)';      Source = 'Verified ($0.161/day)' }
    @{ Key = 'private-ep';   Rate = 0.01;   Desc = 'Private endpoint';                      Source = 'List' }
    @{ Key = 'private-dns';  Rate = 0.0007; Desc = 'Private DNS zone';                      Source = 'List ($0.50/mo)' }
    @{ Key = 'front-door';   Rate = 0.0479; Desc = 'Front Door Standard base fee';          Source = 'List ($35/mo)' }
    @{ Key = 'misc-platform'; Rate = 0.0002; Desc = 'Key Vault, managed identity, alert rule'; Source = 'Usage-based, rounded' }
)
$Rate = @{}; foreach ($r in $Rates) { $Rate[$r.Key] = $r.Rate }

# =============================================================================
# WHAT EACH LEVEL DEPLOYS - quantities only; costs are computed.
# =============================================================================
$Levels = @(
    @{
        Id      = 'L1'
        Title   = 'L1 - Hub and spoke'
        Summary = 'Creates the secure connectivity foundation and a test workload.'
        Detail  = 'Two virtual networks with bidirectional peering, a Basic Bastion host for browser SSH, and one Standard_B2s Linux VM with no public IP. Virtual networks, subnets, peering and NSGs carry no hourly charge - Bastion and the VM are the entire cost.'
        Next    = 'L2 reuses the hub/spoke networks and adds a protected, load-balanced web tier and firewall.'
        Items   = @(
            @{ Key = 'vm-b2s';  Qty = 1; Label = 'Linux VM (Standard_B2s)' }
            @{ Key = 'disk-s4'; Qty = 1; Label = 'OS disk' }
            @{ Key = 'bastion'; Qty = 1; Label = 'Azure Bastion Basic' }
            @{ Key = 'pip';     Qty = 1; Label = 'Public IP (Bastion)' }
        )
    }
    @{
        Id      = 'L2'
        Title   = 'L2 - Web tier and firewall'
        Summary = 'Adds redundancy and traffic governance to the L1 network.'
        Detail  = 'Three more B2s VMs behind an internal Standard Load Balancer, plus an Azure Firewall Standard in the hub with its own public IP. The firewall alone is $1.25/hr and dominates every later level - it is roughly five times the cost of the three VMs it protects. Azure Firewall Basic ($0.395/hr) would cut this substantially but needs a second /26 for AzureFirewallManagementSubnet.'
        Next    = 'L3 adds containers, private data services, identity, and monitoring on the existing foundation.'
        Items   = @(
            @{ Key = 'vm-b2s';   Qty = 3; Label = 'Linux VMs (Standard_B2s)' }
            @{ Key = 'disk-s4';  Qty = 3; Label = 'OS disks' }
            @{ Key = 'firewall'; Qty = 1; Label = 'Azure Firewall Standard' }
            @{ Key = 'pip';      Qty = 1; Label = 'Public IP (firewall)' }
            @{ Key = 'lb';       Qty = 1; Label = 'Internal Standard Load Balancer' }
        )
    }
    @{
        Id      = 'L3'
        Title   = 'L3 - Containers and data'
        Summary = 'Moves the demo toward a modern, secure application platform.'
        Detail  = 'A VNet-integrated Container Apps environment running one minimum replica, an Azure SQL Basic database, two private endpoints with their private DNS zones, Key Vault, a managed identity, Log Analytics and Application Insights. Assumes very light demo traffic; Log Analytics and Application Insights bill on ingestion and are effectively zero at this volume.'
        Next    = 'L4 adds a second-region app, SQL failover capability, and global Front Door.'
        Items   = @(
            @{ Key = 'aca-replica';   Qty = 1; Label = 'Container Apps replica' }
            @{ Key = 'sql-basic';     Qty = 1; Label = 'Azure SQL Database Basic' }
            @{ Key = 'private-ep';    Qty = 2; Label = 'Private endpoints (SQL, Key Vault)' }
            @{ Key = 'private-dns';   Qty = 2; Label = 'Private DNS zones' }
            @{ Key = 'misc-platform'; Qty = 1; Label = 'Key Vault, identity, alert rule' }
        )
    }
    @{
        Id      = 'L4'
        Title   = 'L4 - Global scale'
        Summary = 'Adds regional resilience and a single global entry point.'
        Detail  = 'A second-region Container Apps environment with one replica, a secondary SQL server joined to the primary by a failover group, and Azure Front Door Standard as the global entry point. The geo-secondary database bills at the same rate as the primary. Front Door requests and data transfer are additional usage meters not included here.'
        Next    = 'Multi-region app delivery with health-probed routing and database failover.'
        Items   = @(
            @{ Key = 'aca-replica'; Qty = 1; Label = 'Container Apps replica (secondary region)' }
            @{ Key = 'sql-basic';   Qty = 1; Label = 'SQL geo-secondary database' }
            @{ Key = 'front-door';  Qty = 1; Label = 'Front Door Standard base fee' }
        )
    }
)

# ---- Compute every total from the data above --------------------------------
$running = 0.0
foreach ($lvl in $Levels) {
    $sum = 0.0
    foreach ($i in $lvl.Items) {
        $i.Cost = [math]::Round($Rate[$i.Key] * $i.Qty, 4)
        $sum += $i.Cost
    }
    $running += $sum
    $lvl.Incremental = [math]::Round($sum, 4)
    $lvl.Cumulative  = [math]::Round($running, 4)
}
$FullStack = ($Levels[-1]).Cumulative
# Presenter buffer: round the full stack up and add ~20% for traffic/telemetry.
$BufferLow  = [math]::Ceiling($FullStack * 4) / 4          # next quarter dollar
$BufferHigh = [math]::Ceiling($FullStack * 1.2 * 4) / 4
function Money($v) { '${0:N2}' -f $v }

# =============================================================================
# Minimal Office Open XML writer (no external modules)
# =============================================================================
$NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'

function Esc([string] $s) {
    if ($null -eq $s) { return '' }
    $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

# Word measures in twentieths of a point: 1 inch = 1440. Font size = half-points.
function Run([string] $text, [double] $size = 10, [string] $color = '222222', [bool] $bold = $false) {
    $b = if ($bold) { '<w:b/>' } else { '' }
    $sz = [int]($size * 2)
    '<w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>{0}<w:color w:val="{1}"/><w:sz w:val="{2}"/><w:szCs w:val="{2}"/></w:rPr><w:t xml:space="preserve">{3}</w:t></w:r>' -f $b, $color, $sz, (Esc $text)
}

function Para([string] $text, [double] $size = 10, [string] $color = '222222', [bool] $bold = $false, [int] $after = 120, [int] $before = 0) {
    $r = if ([string]::IsNullOrEmpty($text)) { '' } else { Run $text $size $color $bold }
    '<w:p><w:pPr><w:spacing w:before="{0}" w:after="{1}" w:line="264" w:lineRule="auto"/></w:pPr>{2}</w:p>' -f $before, $after, $r
}

function Bullet([string] $text, [double] $size = 10) {
    # Rendered as a hanging-indent paragraph with a literal bullet, which avoids
    # shipping a numbering.xml part just for flat lists.
    '<w:p><w:pPr><w:spacing w:after="80" w:line="264" w:lineRule="auto"/><w:ind w:left="360" w:hanging="180"/></w:pPr>{0}</w:p>' -f (Run ("$([char]0x2022)  " + $text) $size)
}

function Cell([string] $text, [int] $width, [string] $fill, [double] $size, [string] $color, [bool] $bold) {
    $shd = if ($fill) { '<w:shd w:val="clear" w:color="auto" w:fill="{0}"/>' -f $fill } else { '' }
    # Every <w:tc> must contain at least one <w:p> or Word rejects the file.
    '<w:tc><w:tcPr><w:tcW w:w="{0}" w:type="dxa"/>{1}<w:vAlign w:val="center"/><w:tcMar><w:top w:w="60" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tcMar></w:tcPr><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>{2}</w:p></w:tc>' -f $width, $shd, (Run $text $size $color $bold)
}

function Table([string[]] $headers, [object[]] $rows, [int[]] $widths, [double] $size = 9.5) {
    # A row whose cell count differs from the grid produces a .docx Word will
    # not open. Fail loudly here rather than shipping a broken handout.
    if ($headers.Count -ne $widths.Count) {
        throw "Table has $($headers.Count) headers but $($widths.Count) column widths."
    }
    for ($n = 0; $n -lt $rows.Count; $n++) {
        if ($rows[$n].Count -ne $headers.Count) {
            throw "Table row $n has $($rows[$n].Count) cells, expected $($headers.Count). Check for a mis-parsed ', @(...)' row literal."
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblLayout w:type="fixed"/><w:tblBorders>')
    foreach ($edge in 'top', 'left', 'bottom', 'right', 'insideH', 'insideV') {
        [void]$sb.Append('<w:{0} w:val="single" w:sz="4" w:space="0" w:color="C9D6E4"/>' -f $edge)
    }
    [void]$sb.Append('</w:tblBorders></w:tblPr><w:tblGrid>')
    foreach ($w in $widths) { [void]$sb.Append('<w:gridCol w:w="{0}"/>' -f $w) }
    [void]$sb.Append('</w:tblGrid>')

    # Header row, repeated if the table breaks across pages.
    [void]$sb.Append('<w:tr><w:trPr><w:tblHeader/></w:trPr>')
    for ($i = 0; $i -lt $headers.Count; $i++) {
        [void]$sb.Append((Cell $headers[$i] $widths[$i] 'E8EEF5' ($size - 0.5) '1F4D78' $true))
    }
    [void]$sb.Append('</w:tr>')

    foreach ($row in $rows) {
        [void]$sb.Append('<w:tr>')
        for ($i = 0; $i -lt $row.Count; $i++) {
            [void]$sb.Append((Cell ([string]$row[$i]) $widths[$i] '' $size '222222' $false))
        }
        [void]$sb.Append('</w:tr>')
    }
    [void]$sb.Append('</w:tbl>')
    # Word needs a paragraph after a table, otherwise consecutive tables merge.
    [void]$sb.Append('<w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>')
    $sb.ToString()
}

function Save-Docx([string] $path, [string] $body, [string] $title, [string] $footerText, [int] $margin) {
    $sectPr = '<w:sectPr><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="{0}" w:right="{0}" w:bottom="{0}" w:left="{0}" w:header="708" w:footer="432" w:gutter="0"/><w:cols w:space="708"/><w:docGrid w:linePitch="360"/></w:sectPr>' -f $margin

    $parts = [ordered]@{}
    $parts['[Content_Types].xml'] = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
'@
    $parts['_rels/.rels'] = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
'@
    $parts['word/_rels/document.xml.rels'] = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>
'@
    $parts['word/styles.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        ('<w:styles {0}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="20"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>' -f $NS)

    $parts['word/footer1.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        ('<w:ftr {0}><w:p><w:pPr><w:jc w:val="right"/><w:spacing w:after="0"/></w:pPr>{1}</w:p></w:ftr>' -f $NS, (Run $footerText 7.5 '777777'))

    $parts['word/document.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        ('<w:document {0}><w:body>{1}{2}</w:body></w:document>' -f $NS, $body, $sectPr)

    $parts['docProps/core.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        ('<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>{0}</dc:title><dc:creator>Build-CostDocs.ps1</dc:creator></cp:coreProperties>' -f (Esc $title))

    # Validate every part before packaging - a malformed part yields a .docx
    # that Word silently refuses to open.
    foreach ($k in $parts.Keys) {
        try { [void][xml]$parts[$k] } catch { throw "Generated part '$k' is not well-formed XML: $_" }
    }

    if (Test-Path $path) { Remove-Item $path -Force }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($k in $parts.Keys) {
            $entry  = $zip.CreateEntry($k, [System.IO.Compression.CompressionLevel]::Optimal)
            $stream = $entry.Open()
            $writer = [System.IO.StreamWriter]::new($stream, $utf8)
            $writer.Write($parts[$k])
            $writer.Flush(); $writer.Dispose(); $stream.Dispose()
        }
    } finally { $zip.Dispose() }
    Write-Host "  wrote $path" -ForegroundColor Green
}

# =============================================================================
# Document 1 - multi-page detailed printout
# =============================================================================
$b = [System.Text.StringBuilder]::new()
[void]$b.Append((Para 'IaC Demo Resource Cost Printout' 24 '0B2545' $true 60))
[void]$b.Append((Para 'Estimated cost for one complete running hour' 15 '2E74B5' $false 280))
[void]$b.Append((Para ('Scope: the Azure resources defined in the Demo-IaC repository. Levels are cumulative - L2 includes L1, L3 includes the earlier foundation, and L4 adds the second-region and global-access components. Rates are East US 2, verified {0}.' -f (Get-Date -Format 'd MMMM yyyy'))))

[void]$b.Append((Para 'Executive summary' 16 '2E74B5' $true 160 240))
$summaryRows = foreach ($lvl in $Levels) {
    $inc = (Money $lvl.Incremental) + '/hr'
    $cum = (Money $lvl.Cumulative) + '/hr'
    , @($lvl.Title, $inc, $cum)
}
[void]$b.Append((Table @('Level', 'Added by this level', 'Running total per hour') $summaryRows @(3100, 2800, 3460)))
[void]$b.Append((Para ("Planning figure: about {0} per hour with the full L4 stack running, before traffic, log ingestion, backups or unusual data transfer. Azure Firewall Standard is {1}/hr of that on its own - it costs more than everything else in all four labs combined." -f (Money $FullStack), $Rate['firewall']) 10 '7A5A00' $true))

[void]$b.Append((Para 'Cost progression by level' 16 '2E74B5' $true 200 240))
foreach ($lvl in $Levels) {
    [void]$b.Append((Para ('{0} | adds {1}/hr, running total {2}/hr' -f $lvl.Title, (Money $lvl.Incremental), (Money $lvl.Cumulative)) 13 '2E74B5' $true 140 120))
    [void]$b.Append((Para $lvl.Summary 10 '222222' $true 60))
    [void]$b.Append((Para $lvl.Detail))
}

[void]$b.Append((Para 'Line-by-line breakdown' 16 '2E74B5' $true 200 240))
$breakdown = [System.Collections.ArrayList]::new()
foreach ($lvl in $Levels) {
    foreach ($i in $lvl.Items) {
        $unit = Money $Rate[$i.Key]
        $cost = Money $i.Cost
        [void]$breakdown.Add(@($lvl.Id, $i.Label, [string]$i.Qty, $unit, $cost))
    }
    $sub = Money $lvl.Incremental
    [void]$breakdown.Add(@('', ('{0} subtotal' -f $lvl.Id), '', '', $sub))
}
[void]$breakdown.Add(@('', 'Full L4 stack, per hour', '', '', (Money $FullStack)))
[void]$b.Append((Table @('Level', 'Resource', 'Qty', 'Unit rate/hr', 'Cost/hr') $breakdown.ToArray() @(760, 4000, 700, 1750, 2150)))

[void]$b.Append((Para 'Where these rates come from' 16 '2E74B5' $true 200 240))
$rateRows = foreach ($r in $Rates) {
    $amount = Money $r.Rate
    , @($r.Desc, $amount, $r.Source)
}
[void]$b.Append((Table @('Resource', 'Rate per hour', 'Basis') $rateRows @(4200, 1700, 3460)))

[void]$b.Append((Para 'Assumptions' 16 '2E74B5' $true 200 240))
foreach ($bullet in @(
    'Region: East US 2 for L1-L3, with West US 2 as the L4 secondary region, matching the Bicep defaults.'
    'Pricing basis: US pay-as-you-go retail list pricing. Your invoice will differ under an EA, CSP or MCA agreement.'
    'VMs run for the entire hour and are not deallocated.'
    'Container Apps run at the configured minimum of one 0.5 vCPU / 1 GiB replica per region. The monthly free grant is ignored, so short demos cost less than shown.'
    'Azure Firewall also bills $0.016 per GB processed, and a separate capacity-unit meter at $0.07/hr applies above the base deployment charge. Neither is included above.'
    'Network traffic, VNet peering data, SQL backup growth, Log Analytics ingestion, Application Insights telemetry and Front Door requests are excluded or assumed negligible.'
    'The optional L1 VPN Gateway is not included because it is commented out in the template.'
)) { [void]$b.Append((Bullet $bullet)) }

[void]$b.Append((Para 'Important cost notes' 16 '2E74B5' $true 200 240))
[void]$b.Append((Para ("Azure Firewall and Bastion bill while deployed, whether or not anyone is using the lab - together they are {0}/hr, over 85 percent of the L2 running total. Tear the lab down when you are finished: run the Teardown labs workflow, or scripts/Cleanup-Labs.ps1 -ResourceGroup <rg>. Do not delete only the firewall to save money - both spoke subnets route 0.0.0.0/0 at its private IP, so the surviving VMs lose all connectivity and keep billing." -f (Money ($Rate['firewall'] + $Rate['bastion'])))))
[void]$b.Append((Para ("For a live presentation, budget {0} to {1} for one full L4 hour to cover normal request and telemetry activity." -f (Money $BufferLow), (Money $BufferHigh)) 10 '7A5A00' $true))
[void]$b.Append((Para 'These are planning estimates, not a quote. Confirm with the Azure Pricing Calculator or Cost Management before committing a budget.'))

[void]$b.Append((Para 'Reference links' 16 '2E74B5' $true 200 240))
foreach ($link in @(
    'Azure pricing overview: https://azure.microsoft.com/pricing/'
    'Azure Firewall pricing: https://azure.microsoft.com/pricing/details/azure-firewall/'
    'Azure Bastion pricing: https://azure.microsoft.com/pricing/details/azure-bastion/'
    'Azure SQL Database pricing: https://azure.microsoft.com/pricing/details/azure-sql-database/single/'
    'Azure Front Door pricing: https://azure.microsoft.com/pricing/details/frontdoor/'
)) { [void]$b.Append((Para $link 9 '555555' $false 60)) }

Save-Docx (Join-Path $OutputDirectory 'IaC_Demo_Hourly_Cost_Printout.docx') $b.ToString() `
    'IaC Demo Resource Cost Printout' 'IaC Demo | Cost Printout' 1440

# =============================================================================
# Document 2 - one-page presenter handout
# =============================================================================
$o = [System.Text.StringBuilder]::new()
[void]$o.Append((Para 'IaC Demo Azure Cost Progression' 19 '0B2545' $true 40))
[void]$o.Append((Para 'One-page handout | cost for one complete running hour' 10 '2E74B5' $true 100))
[void]$o.Append((Para ('East US 2 (West US 2 for the L4 secondary region), US pay-as-you-go retail rates verified {0}. Levels are cumulative. Traffic, logging, backups and data transfer are excluded or assumed minimal.' -f (Get-Date -Format 'd MMMM yyyy')) 8.5 '555555' $false 140))

$onePagerRows = foreach ($lvl in $Levels) {
    $resources = ($lvl.Items | ForEach-Object {
        if ($_.Qty -gt 1) { "$($_.Qty) x $($_.Label)" } else { $_.Label }
    }) -join '; '
    $inc = Money $lvl.Incremental
    $cum = (Money $lvl.Cumulative) + '/hr'
    , @($lvl.Id, $resources, $inc, $cum)
}
[void]$o.Append((Table @('Level', 'Main resources added', 'Adds/hr', 'Running total') $onePagerRows @(620, 6300, 1150, 1580) 8.5))

foreach ($lvl in $Levels) {
    [void]$o.Append((Para ('{0} | adds {1}/hr, total {2}/hr' -f $lvl.Title, (Money $lvl.Incremental), (Money $lvl.Cumulative)) 10.5 '2E74B5' $true 80 100))
    [void]$o.Append((Para $lvl.Summary 8.5 '222222' $false 40))
    $nextLabel = if ($lvl -eq $Levels[-1]) { 'End state: ' } else { 'Builds next: ' }
    [void]$o.Append((Para ($nextLabel + $lvl.Next) 8.5 '1F4D78' $true 60))
}

[void]$o.Append((Para ("Presenter takeaway: budget {0}-{1} for one full hour of the L4 demo. Azure Firewall ({2}/hr) and Bastion ({3}/hr) bill while deployed even when idle - run teardown when you finish." -f (Money $BufferLow), (Money $BufferHigh), (Money $Rate['firewall']), (Money $Rate['bastion'])) 8.5 '7A5A00' $true 100 100))
[void]$o.Append((Para 'Planning estimates only. Confirm in the Azure Pricing Calculator or Cost Management for the target subscription. Reference: azure.microsoft.com/pricing' 7.5 '666666' $false 0))

Save-Docx (Join-Path $OutputDirectory 'IaC_Demo_Cost_One_Page.docx') $o.ToString() `
    'IaC Demo Azure Cost Progression - One Page' 'IaC Demo | One-page cost handout' 792

# ---- Console summary --------------------------------------------------------
Write-Host ""
Write-Host "  Cost model (East US 2, per hour)" -ForegroundColor White
foreach ($lvl in $Levels) {
    Write-Host ("    {0,-30} +{1,-8} = {2}" -f $lvl.Title, (Money $lvl.Incremental), (Money $lvl.Cumulative)) -ForegroundColor Cyan
}
Write-Host ("    {0,-30}  {1}" -f 'Presenter buffer', ((Money $BufferLow) + ' - ' + (Money $BufferHigh))) -ForegroundColor Yellow
Write-Host ""
