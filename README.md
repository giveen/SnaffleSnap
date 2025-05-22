# SnaffleSnap

**SnaffleSnap** is a fast, lightweight PowerShell parser and reporter for [Snaffler](https://github.com/SnaffCon/Snaffler) logs — designed to give you clear, color-coded insights in seconds.

Inspired by the awesome work of [Efflanrs](https://github.com/CyberCX-STA/efflanrs), SnaffleSnap focuses on simplicity and speed, helping analysts quickly sift through log noise and highlight what matters most.

## Features

- Parses JSON, TXT, and LOG Snaffler output files seamlessly  
- Color-coded HTML reports sorted by severity: Black, Red, Yellow, Green  
- Extracts file rights, timestamps, and context for easy triage  
- CSV export for integration with other tools  
- Customizable sorting (Rating, Rights, Filename, CreationTime, LastWriteTime)  

## Usage

```powershell
.\SnaffleSnap.ps1 -FilePath <path_to_snaffler_log> [-SortBy <property>] [-Help]
