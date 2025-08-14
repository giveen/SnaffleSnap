
param (
    [string]$FilePath,
    [switch]$Help,
    [string]$SortBy = "Rating"
)

function Show-Help {
@"
Usage: .\script.ps1 -FilePath <path> [-SortBy <property>] [-Help]
Parameters:
 -FilePath Path to the Snaffler log file (.json, .txt, .log)
 -SortBy Property to sort by after Severity. Options:
   Rating, Rights, FullName, CreationTime, LastWriteTime, Hostname
 Default is 'Rating'
 -Help, -h Show this help message
Note: Results are always primarily sorted by severity order:
 Black > Red > Yellow > Green > Others
"@
    Write-Host
}

function Extract-Hostname {
    param([string]$fullPath)
    if ([string]::IsNullOrWhiteSpace($fullPath)) { return "" }
    if ($fullPath -match '^\\\\([^\\]+)') {
        return $matches[1]
    }
    return ""
}

function Parse-TxtFile {
    param($Path)
    $results = @()
    $regex = '\[File\] \{(?<Rating>\w+)\}<[^|]+\|(?<Rights>R|RW)\|[^|]*\|[^|]*\|(?<Timestamp>[^>]+)>\((?<FullPath>\\\\[^)]+)\)\s*(?<Context>.*)?'

    foreach ($line in Get-Content $Path -Encoding Default) {
        if ($line -match $regex) {
            $rating = $matches['Rating']
            $rights = $matches['Rights']
            $fullName = $matches['FullPath']
            $hostname = Extract-Hostname $fullName
            $creationTime = $matches['Timestamp']
            $context = $matches['Context']

            $results += [PSCustomObject]@{
                Rating = $rating
                Rights = $rights
                FullName = $fullName
                Hostname = $hostname
                CreationTime = $creationTime
                LastWriteTime = $creationTime
                Context = $context
            }
        }
    }
    return $results
}

function Generate-HTML {
    param([array]$Findings)
    $html = @"
<html>
<head>
    <style>
        body { font-family: Arial; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; }
        th { background-color: #f2f2f2; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
    <h2>Snaffler Deduplicated Findings Report</h2>
    <table>
        <tr>
            <th>FileName</th>
            <th>Rating</th>
            <th>Rights</th>
            <th>Hostnames</th>
            <th>FullPaths</th>
            <th>CreationTime</th>
            <th>LastWriteTime</th>
            <th>Context</th>
        </tr>
"@
    foreach ($finding in $Findings) {
        $html += "<tr><td>$($finding.FileName)</td><td>$($finding.Rating)</td><td>$($finding.Rights)</td><td>$($finding.Hostnames)</td><td><pre>$($finding.FullPaths)</pre></td><td>$($finding.CreationTime)</td><td>$($finding.LastWriteTime)</td><td><pre>$($finding.Context)</pre></td></tr>"
    }
    $html += "</table></body></html>"
    $html | Out-File -FilePath "Snaffler_Report.html"
}

function Output-CSV {
    param([array]$Findings)

    if (-not $Findings -or $Findings.Count -eq 0) {
        Write-Host "No findings to export to CSV."
        return
    }

    $csvPath = "Snaffler_Report_cleaned.csv"

    $cleanedFindings = $Findings | ForEach-Object {
        [PSCustomObject]@{
            FileName      = $_.FileName
            Rating        = $_.Rating
            Rights        = $_.Rights
            Hostnames     = $_.Hostnames
            FullPaths     = ($_.FullPaths -replace '[\r\n]+', ' ') -replace '"', '""'
            CreationTime  = $_.CreationTime
            LastWriteTime = $_.LastWriteTime
            Context       = ($_.Context -replace '[\r\n]+', ' ') -replace '"', '""'
        }
    }

    # Export with manual quoting to handle embedded commas and quotes
    $csvContent = @()
    $headers = "FileName","Rating","Rights","Hostnames","FullPaths","CreationTime","LastWriteTime","Context"
    $csvContent += ($headers -join ",")

    foreach ($row in $cleanedFindings) {
        $line = $headers | ForEach-Object {
            '"' + ($row.$_ -replace '"', '""') + '"'
        }
        $csvContent += ($line -join ",")
    }

    $csvContent | Set-Content -Path $csvPath -Encoding UTF8
    Write-Host "Cleaned CSV report saved as $csvPath"
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

# Validate sorting property
$validProps = @("Rating", "Rights", "FullName", "CreationTime", "LastWriteTime", "Hostname")
if ($SortBy -notin $validProps) {
    Write-Host "Invalid sort property '$SortBy'. Valid options: $($validProps -join ', ')"
    exit
}

# Define severity order map
$severityMap = @{
    Black = 0
    Red = 1
    Yellow = 2
    Green = 3
    Default = 4
}

# Add severity rank property
$findings | ForEach-Object {
    $severityValue = if ($severityMap.ContainsKey($_.Rating)) { $severityMap[$_.Rating] } else { $severityMap['Default'] }
    $_ | Add-Member -NotePropertyName SeverityRank -NotePropertyValue $severityValue -Force
}

# Sort primarily by SeverityRank, secondarily by SortBy property
$sortedFindings = $findings | Sort-Object -Property @{Expression = 'SeverityRank'; Ascending = $true}, @{Expression = $SortBy; Ascending = $true}

# Deduplicate based on file name
$dedupedFindings = $sortedFindings | Group-Object {
    [System.IO.Path]::GetFileName($_.FullName)
} | ForEach-Object {
    $group = $_.Group
    $first = $group | Select-Object -First 1
    [PSCustomObject]@{
        FileName      = $_.Name
        Rating        = $first.Rating
        Rights        = $first.Rights
        Hostnames     = ($group | Select-Object -ExpandProperty Hostname | Sort-Object -Unique) -join ", "
        FullPaths     = ($group | Select-Object -ExpandProperty FullName | Sort-Object -Unique) -join "`n"
        CreationTime  = $first.CreationTime
        LastWriteTime = $first.LastWriteTime
        Context       = $first.Context
    }
}

# Output
Generate-HTML -Findings $dedupedFindings
Output-CSV -Findings $dedupedFindings
