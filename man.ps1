# === CONFIGURATION ===
$vmWindowTitle = "Windows 10"  # Change to your VM window title exactly

function Safe-SetClipboard {
    param (
        [string]$Text,
        [int]$MaxRetries = 5,
        [int]$DelayMs = 500
    )

    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            Set-Clipboard -Value $Text
            Write-Host " Clipboard set (attempt $($i+1))"
            return $true
        } catch {
            Write-Warning " Clipboard in use. Retrying in $DelayMs ms..."
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    Write-Error " Failed to set clipboard after $MaxRetries attempts."
    return $false
}

# Create WScript.Shell COM object
$wshell = New-Object -ComObject WScript.Shell

# Activate VMware Horizon Client window
if (-not $wshell.AppActivate($vmWindowTitle)) {
    Write-Host " Could not activate VM window titled '$vmWindowTitle'. Make sure it's open and visible."
    exit
}

$sourceZip = "C:\Users\hoanghv-os\Downloads\MobaXterm_Portable_v25.2.zip"
$chunkSize = 1023kB  # in characters (~3KB binary when base64-encoded)
# Read file and convert to base64
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourceZip))

# Split into chunks
$chunks = ($base64 -split "(.{$chunkSize})" | Where-Object { $_ -ne "" })

# === Build multiline PowerShell command for VM ===
$command = @"
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms
`$f = 'C:\Users\Public\clipboard_content.txt'
`$f_bin = 'C:\Users\Public\bin.b64'
Remove-Item -Path `$f -ErrorAction Ignore
Remove-Item -Path `$f_bin -ErrorAction Ignore

`$lastText = ''
while (`$true) {
    try {
	`$currentText = [Windows.Clipboard]::GetText()
    } catch {
        Start-Sleep -Milliseconds 500
        continue
    }

    if (`$currentText -eq 'end') {
        Write-Host 'Received end command. Exiting.'
	`$outputZip  = "C:\Users\Public\received.zip"

	# Read entire base64 string (as one block)
	`$base64String = Get-Content -Path `$f_bin -Raw

# Convert base64 string to binary
	`$zipBytes = [Convert]::FromBase64String(`$base64String)

# Write binary bytes to actual ZIP file
	[System.IO.File]::WriteAllBytes(`$outputZip, `$zipBytes)

	Write-Host "ZIP file reconstructed at: `$outputZip"
        break
    }

    if (![string]::IsNullOrWhiteSpace(`$currentText) -and 
        (`$currentText -ne `$lastText)) {

        if (`$currentText -match '^\[[^\]]+\]\s*(.+)$') {
            	`$contentOnly = `$matches[1]
        	`$stream = [System.IO.StreamWriter]::new(`$f_bin, `$true)
        	`$stream.Write(`$contentOnly)  # prepend space to separate entries
        	`$stream.Close()
        Add-Content -Path `$f -Value `$currentText
	
        }

	`$now = Get-Date
        Write-Host \"Appended clipboard content at `$now\"

        `$lastText = `$currentText
    }

    Start-Sleep -Milliseconds 2000
}
"@

# Copy command to clipboard
$command | Set-Clipboard
Write-Host "Command copied to clipboard."

Start-Sleep -Milliseconds 1000
# Paste the command into VM PowerShell prompt
$wshell.SendKeys("^v")

cmd.exe /c "echo off | clip"

$wshell.SendKeys("{ENTER}")
Write-Host "Command pasted and executed inside VM PowerShell."

# Send chunks
$i = 0
foreach ($chunk in $chunks) {
    Write-Host "Sending chunk $i of $($chunks.Count)"
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $context = "[$time] $chunk"
    # Wait until VM signals ready (clipboard contains [ACK]) before sending next chunk


if (-not (Safe-SetClipboard -Text $context)) {
    Write-Error "Chunk failed to send. Aborting."
    break
}
	
    Start-Sleep -Milliseconds 2000  # give VM time to read
    $i++
}

Start-Sleep -Milliseconds 1000
$text = "end"
"$text" | Set-Clipboard
