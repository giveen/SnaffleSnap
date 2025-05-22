param (
    [string]$FilePath,
    [switch]$Help,
    [string]$SortBy = "Rating"
)

function Show-Help {
    @"
Usage: .\script.ps1 -FilePath <path> [-SortBy <property>] [-Help]

Parameters:
  -FilePath   Path to the Snaffler log file (.json, .txt, .log)
  -SortBy     Property to sort by after Severity. Options:
                Rating, Rights, FullName, CreationTime, LastWriteTime, Hostname
              Default is 'Rating'
  -Help, -h   Show this help message

Note: Results are always primarily sorted by severity order:
      Black > Red > Yellow > Green > Others
"@ | Write-Host
}

function ConvertTo-HtmlSafe {
    param ([string]$Text)
    return $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
}

function Show-Banner {
    Write-Host ".,:::::: .-:::::'.-:::::' :::      :::.    ::.    :::.  :::::::.. .::::::.:" -ForegroundColor Cyan
    Write-Host ";;;;'''' ;;;'''' ;;;''''  ;;;      ;;`;;   ;;;;,  `;;; ;;;;``;;;;;;;`    ``" -ForegroundColor Cyan
    Write-Host " [[cccc  [[[,,== [[[,,==  [[[     ,[[ '[[,  [[[[[. '[[  [[[,/[[[''[==/[[[[," -ForegroundColor Cyan
    Write-Host " $$      `$$$'`` `$$$'``  $$'    c$$$cc$$$c $$$ 'Y$c$$   $$$$$$c   '''    $" -ForegroundColor Cyan
    Write-Host "888oo,__  888     888   o88oo,.__888   888,888    Y88  888b '88bo,88b    dP" -ForegroundColor Cyan
    Write-Host "M''''YUM   'MM,    'MM,  ''''YUMM YMM   ''` MMM     YMMMMMMM   'W'  'YMmMY'" -ForegroundColor Cyan
}

# Helper function to extract hostname from UNC path (e.g. \\hostname\share\file)
function Extract-Hostname {
    param([string]$fullPath)
    if ([string]::IsNullOrWhiteSpace($fullPath)) { return "" }
    if ($fullPath -match '^\\\\([^\\]+)') {
        return $matches[1]
    }
    return ""
}

function Parse-JsonFile {
    param ($Path)
    $json = Get-Content $Path -Raw | ConvertFrom-Json
    $results = @()

    foreach ($entry in $json.entries) {
        if ($entry.level -eq "Warn") {
            foreach ($eventProperty in $entry.eventProperties.PSObject.Properties) {
                foreach ($fileProperty in $eventProperty.Value.PSObject.Properties) {
                    if ($fileProperty.Value.MatchedRule) {
                        $rating = $fileProperty.Value.MatchedRule.Triage
                        $fileInfo = $fileProperty.Value.FileResult.FileInfo
                        $hostname = Extract-Hostname $fileInfo.FullName
                        $results += [PSCustomObject]@{
                            Rating        = $rating
                            Rights        = ""  # No Rights info in JSON, keep blank
                            FullName      = $fileInfo.FullName
                            Hostname      = $hostname
                            CreationTime  = $fileInfo.CreationTime
                            LastWriteTime = $fileInfo.LastWriteTime
                            Context       = ""
                        }
                    }
                }
            }
        }
    }
    return $results
}

function Parse-TxtFile {
    param ($Path)
    $results = @()
    $fileRegex = "\[File\].*?\{(?<Rating>.*?)\}.*?<[^>]*\|(?<Rights>R|RW)\|[^>]*>\(\\{2}.*?\)(?<Context>.+)?"

    foreach ($line in Get-Content $Path -Encoding Default) {
        if ($line -match $fileRegex) {
            $rating       = $matches['Rating']
            $rights       = $matches['Rights']
            $context      = if ($matches['Context']) { $matches['Context'].Trim() } else { "" }
            
            if ($line -match "\((?<FullPath>\\\\.*?)\)") {
                $fullName = $matches['FullPath']
            } else {
                $fullName = ""
            }

            $hostname = Extract-Hostname $fullName

            $creationTime = $null
            if ($line -match "\|(\d{4}-\d{2}-\d{2}.*?)Z") {
                try { $creationTime = [datetime]$matches[1] } catch {}
            }

            $results += [PSCustomObject]@{
                Rating        = $rating
                Rights        = $rights
                FullName      = $fullName
                Hostname      = $hostname
                CreationTime  = $creationTime
                LastWriteTime = $null
                Context       = $context
            }
        }
    }
    return $results
}

function Generate-HTML {
    param ($Findings)
    $html = @"
<html>
<head>
    <title>Snaffler Findings</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #999; padding: 8px; text-align: left; vertical-align: top; }
        th { background-color: #f2f2f2; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
<h2>Snaffler Findings</h2>
<table>
<tr><th>Rating</th><th>Rights</th><th>Hostname</th><th>Full Name</th><th>Creation Time</th><th>Last Write Time</th><th>Context</th></tr>
"@

    foreach ($f in $Findings) {
        $color = switch ($f.Rating) {
            "Red"    { "#ffcccc" }
            "Yellow" { "#ffffcc" }
            "Green"  { "#ccffcc" }
            "Black"  { "#444444"; $f.Context = "<span style='color:white'>" + (ConvertTo-HtmlSafe $f.Context) + "</span>" }
            default  { "#ffffff" }
        }

        $creation = if ($f.CreationTime) { $f.CreationTime } else { "" }
        $lastWrite = if ($f.LastWriteTime) { $f.LastWriteTime } else { "" }

        $contextHtml = if ($f.Rating -eq "Black") { $f.Context } else { "<pre>" + (ConvertTo-HtmlSafe $f.Context) + "</pre>" }

        $html += "<tr style='background-color:$color;'><td>$($f.Rating)</td><td>$($f.Rights)</td><td>$($f.Hostname)</td><td>$($f.FullName)</td><td>$creation</td><td>$lastWrite</td><td>$contextHtml</td></tr>`n"
    }

    $html += "</table></body></html>"
    $html | Out-File -FilePath "report.html" -Encoding UTF8
    Start-Process "report.html"
}

function Output-CSV {
    param ($Findings)
    $Findings | Export-Csv -Path "report.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "CSV report generated as report.csv"
}

# Main Execution
if ($Help -or $args -contains "-h") {
    Show-Help
    exit
}

if (-not $FilePath) {
    Write-Host "Please provide a .json or .txt/.log file as a parameter. Use -Help for usage info."
    exit
}

# Parse input file
if ($FilePath -like "*.json") {
    Write-Host "Parsing JSON file..."
    $findings = Parse-JsonFile -Path $FilePath
} elseif ($FilePath -like "*.txt" -or $FilePath -like "*.log") {
    Write-Host "Parsing TXT/LOG file..."
    $findings = Parse-TxtFile -Path $FilePath
} else {
    Write-Host "Unknown file type. Attempting JSON first..."
    try {
        $findings = Parse-JsonFile -Path $FilePath
    } catch {
        Write-Host "Failed to parse as JSON. Trying TXT..."
        try {
            $findings = Parse-TxtFile -Path $FilePath
        } catch {
            Write-Host "Unrecognized file format. Exiting."
            exit
        }
    }
}

# Validate sorting property (add Hostname)
$validProps = @("Rating", "Rights", "FullName", "CreationTime", "LastWriteTime", "Hostname")
if ($SortBy -notin $validProps) {
    Write-Host "Invalid sort property '$SortBy'. Valid options: $($validProps -join ', ')"
    exit
}

# Define severity order map
$severityMap = @{
    Black  = 0
    Red    = 1
    Yellow = 2
    Green  = 3
    Default = 4
}

# Add severity rank property
$findings | ForEach-Object {
    $severityValue = if ($severityMap.ContainsKey($_.Rating)) { $severityMap[$_.Rating] } else { $severityMap['Default'] }
    $_ | Add-Member -NotePropertyName SeverityRank -NotePropertyValue $severityValue -Force
}

# Sort primarily by SeverityRank, secondarily by SortBy property
$sortedFindings = $findings | Sort-Object -Property @{Expression = 'SeverityRank'; Ascending = $true}, @{Expression = $SortBy; Ascending = $true}

# Output
Generate-HTML -Findings $sortedFindings
Output-CSV -Findings $sortedFindings
