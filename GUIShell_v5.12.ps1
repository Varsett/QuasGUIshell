<#
.SYNOPSIS
    Quas GUI Shell v5.0.1
    created by Varset & Gemini Dev, refactored by Claude
.DESCRIPTION
    Changes from v4.9.1:
    - NEW: Dynamic TabControl (+ button creates, x closes, double-click renames)
    - NEW: Each tab has its own editor and log (variant B)
    - NEW: Detach Log opens the log of the active tab
    - NEW: Status bar (tab name, line count)
    - NEW: Timestamps toggle [HH:mm:ss] in log
    - NEW: Ctrl+T new tab, Ctrl+W close tab, Ctrl+Tab next tab
    - KEEP: All v4.9.1 features (TreeView, themes, search, deep sync, etc.)
#>
param (
    [string]$ToolsPath = ""
)

# --- Path Processing ---
if ($ToolsPath) {
    $cleanPath = $ToolsPath.Replace('"', '').TrimEnd('\')
    $env:PATH  = "$cleanPath;" + $env:PATH
    $script:tPath = $cleanPath + "\"
} else {
    $script:tPath = ""
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:isStopping     = $false
$script:isDarkMode     = $true
$script:lastCodeBackup = ""
$script:lastLogBackup  = ""
$script:highlightColor = [System.Drawing.Color]::FromArgb(255, 255, 180)
$script:showTimestamps = $true
$script:tabs           = [System.Collections.Generic.List[hashtable]]::new()
$script:activeTabIdx   = 0

# ---------------------------------------------------------------------------
# 1. HINTS LOADING
# ---------------------------------------------------------------------------
# Search order for hints.txt:
#   1. -ToolsPath folder (if provided)
#   2. Same folder as the script ($PSScriptRoot)
#   3. Source subfolder next to script ($PSScriptRoot\Source)
#   4. $env:myfiles (legacy Quas env variable)
function Find-HintsFile {
    $candidates = @()
    if ($script:tPath) { $candidates += Join-Path $script:tPath "hints.txt" }
    if ($PSScriptRoot) {
        $candidates += Join-Path $PSScriptRoot "hints.txt"
        $candidates += Join-Path $PSScriptRoot "Source\hints.txt"
    }
    if ($env:myfiles) { $candidates += Join-Path $env:myfiles "hints.txt" }
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}
$hintsFile = Find-HintsFile

function Parse-HintsFile($path) {
    $cats    = [System.Collections.Specialized.OrderedDictionary]::new()
    $current = "General"
    $cats[$current] = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path $path)) { return $cats }
    foreach ($line in (Get-Content $path)) {
        if ($line -match '^\[(.+)\]') {
            $current = $Matches[1].Trim()
            if (-not $cats.Contains($current)) { $cats[$current] = [System.Collections.Generic.List[string]]::new() }
            continue
        }
        if ($line -match '^#\s*[-=]{3,}\s*(.+?)\s*[-=]{3,}\s*$') {
            $current = $Matches[1].Trim()
            if (-not $cats.Contains($current)) { $cats[$current] = [System.Collections.Generic.List[string]]::new() }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if (-not $cats.Contains($current)) { $cats[$current] = [System.Collections.Generic.List[string]]::new() }
        $cats[$current].Add($line.Trim())
    }
    $emptyKeys = @($cats.Keys | Where-Object { $cats[$_].Count -eq 0 })
    foreach ($k in $emptyKeys) { $cats.Remove($k) }
    return $cats
}
$script:hintCategories = Parse-HintsFile $hintsFile

# ---------------------------------------------------------------------------
# 2. FONTS & COLORS
# ---------------------------------------------------------------------------
$font     = New-Object System.Drawing.Font("Consolas", 11)
$uiFont   = New-Object System.Drawing.Font("Segoe UI", 10)
$boldFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$script:catColors = @(
    [System.Drawing.Color]::FromArgb(100,180,255),
    [System.Drawing.Color]::FromArgb(100,220,180),
    [System.Drawing.Color]::FromArgb(255,180, 80),
    [System.Drawing.Color]::FromArgb(220,120,120),
    [System.Drawing.Color]::FromArgb(160,210,100),
    [System.Drawing.Color]::FromArgb(190,150,255),
    [System.Drawing.Color]::FromArgb(255,220,100),
    [System.Drawing.Color]::FromArgb(130,200,230),
    [System.Drawing.Color]::FromArgb(200,170,130)
)

# ---------------------------------------------------------------------------
# 3. TREEVIEW
# ---------------------------------------------------------------------------
# Hint line prefixes (stripped before display and insert):
#   !cmd  -> red    (dangerous: deletes data, irreversible)
#   ~cmd  -> yellow (caution: changes settings/state)
#   cmd   -> normal (safe/informational)
$script:hintColorDanger  = [System.Drawing.Color]::FromArgb(255, 90,  90)
$script:hintColorCaution = [System.Drawing.Color]::FromArgb(255, 210,  60)

function Get-HintParts($raw) {
    # Returns hashtable: .Cmd (clean command), .Color (node forecolor or $null for default)
    if ($raw.StartsWith('!')) {
        return @{ Cmd=$raw.Substring(1).TrimStart(); Color=$script:hintColorDanger }
    } elseif ($raw.StartsWith('~')) {
        return @{ Cmd=$raw.Substring(1).TrimStart(); Color=$script:hintColorCaution }
    } else {
        return @{ Cmd=$raw; Color=$null }
    }
}

function Populate-HintTree($tree, $filterText) {
    $tree.BeginUpdate(); $tree.Nodes.Clear()
    $q = $filterText.ToLower(); $ci = 0
    foreach ($catKey in $script:hintCategories.Keys) {
        $items    = $script:hintCategories[$catKey]
        # Filter against clean command text (strip prefix for matching)
        $filtered = if ($q) {
            @($items | Where-Object { (Get-HintParts $_).Cmd.ToLower().Contains($q) })
        } else { @($items) }
        if ($filtered.Count -eq 0) { continue }

        $catColor = $script:catColors[$ci % $script:catColors.Count]; $ci++
        $cn = New-Object System.Windows.Forms.TreeNode
        $cn.Text = $catKey; $cn.ToolTipText = "$($filtered.Count) commands"
        $cn.Tag = $null; $cn.ForeColor = $catColor; $cn.NodeFont = $boldFont

        foreach ($raw in $filtered) {
            $parts = Get-HintParts $raw
            $nd = New-Object System.Windows.Forms.TreeNode
            $nd.Text = $parts.Cmd
            $nd.Tag  = $parts.Cmd   # clean cmd inserted into editor
            # Tooltip shows danger/caution label
            $nd.ToolTipText = if ($raw.StartsWith('!')) {
                "[DANGER] $($parts.Cmd)"
            } elseif ($raw.StartsWith('~')) {
                "[CAUTION] $($parts.Cmd)"
            } else {
                $parts.Cmd
            }
            if ($null -ne $parts.Color) { $nd.ForeColor = $parts.Color }
            [void]$cn.Nodes.Add($nd)
        }
        [void]$tree.Nodes.Add($cn)
        if ($q) { $cn.Expand() } else { $cn.Collapse() }
    }
    $tree.EndUpdate()
}

# ---------------------------------------------------------------------------
# 4. TAB HELPERS
# ---------------------------------------------------------------------------
function Get-ActiveTab {
    if ($script:tabs.Count -eq 0) { return $null }
    return $script:tabs[$script:activeTabIdx]
}
function Get-ActiveCmdBox { $t = Get-ActiveTab; if ($t) { return $t.CmdBox } else { return $null } }
function Get-ActiveLogBox { $t = Get-ActiveTab; if ($t) { return $t.LogBox } else { return $null } }

function New-TabData($name) {
    $cb = New-Object System.Windows.Forms.RichTextBox -Property @{
        Dock="Fill"; Font=$font; ScrollBars="Vertical"
        BackColor=[System.Drawing.Color]::FromArgb(45,45,45)
        ForeColor=[System.Drawing.Color]::FromArgb(240,240,240)
        BorderStyle="None"; AcceptsTab=$true
    }
    $lb = New-Object System.Windows.Forms.RichTextBox -Property @{
        Dock="Fill"; ReadOnly=$true; Font=$font
        BackColor=[System.Drawing.Color]::FromArgb(35,35,35)
        ForeColor=[System.Drawing.Color]::FromArgb(240,240,240)
        BorderStyle="None"
    }
    return @{ Name=$name; CmdBox=$cb; LogBox=$lb }
}

function Update-StatusBar {
    $t = Get-ActiveTab
    if ($null -eq $t) { $script:statusLabel.Text = "No tabs"; return }
    $lines = $t.CmdBox.Lines.Count
    $script:statusLabel.Text = "Tab: $($t.Name)  |  Lines: $lines"
}

# Build the tab strip from scratch each time
function Refresh-TabStrip {
    $script:tabStrip.SuspendLayout()
    $script:tabStrip.Controls.Clear()

    for ($i = 0; $i -lt $script:tabs.Count; $i++) {
        $idx      = $i
        $tab      = $script:tabs[$i]
        $isActive = ($i -eq $script:activeTabIdx)

        # Tab panel
        $pnl = New-Object System.Windows.Forms.Panel -Property @{
            Width=140; Height=30
            Margin=New-Object System.Windows.Forms.Padding(2,2,0,0)
            BackColor=if($isActive){[System.Drawing.Color]::FromArgb(65,65,65)}else{[System.Drawing.Color]::FromArgb(38,38,38)}
        }

        # Tab label
        $lbl = New-Object System.Windows.Forms.Label -Property @{
            Text=$tab.Name; Left=6; Top=6; Width=104; Height=18
            ForeColor=if($isActive){[System.Drawing.Color]::White}else{[System.Drawing.Color]::FromArgb(150,150,150)}
            Font=if($isActive){$boldFont}else{$uiFont}
            Cursor="Hand"
        }
        $lbl.Tag = $idx

        # Close [x] label
        $xBtn = New-Object System.Windows.Forms.Label -Property @{
            Text="x"; Left=116; Top=6; Width=18; Height=18
            ForeColor=[System.Drawing.Color]::FromArgb(130,130,130)
            Font=$uiFont; TextAlign="MiddleCenter"; Cursor="Hand"
        }
        $xBtn.Tag = $idx

        # Active tab indicator line at bottom
        if ($isActive) {
            $bar = New-Object System.Windows.Forms.Panel -Property @{
                Left=0; Top=28; Width=140; Height=2
                BackColor=[System.Drawing.Color]::FromArgb(100,180,255)
            }
            $pnl.Controls.Add($bar)
        }

        # Events - switch
        $lbl.Add_Click({
            param($s,$e)
            $script:activeTabIdx = [int]$s.Tag
            Switch-Tab
        })
        # Events - rename
        $lbl.Add_DoubleClick({
            param($s,$e)
            $tidx = [int]$s.Tag
            $inp  = [Microsoft.VisualBasic.Interaction]::InputBox("New tab name:", "Rename Tab", $script:tabs[$tidx].Name)
            if ($inp -and $inp.Trim()) {
                $script:tabs[$tidx].Name = $inp.Trim()
                Refresh-TabStrip; Update-StatusBar
            }
        })
        # Events - close
        $xBtn.Add_Click({
            param($s,$e)
            if ($script:tabs.Count -le 1) { return }
            $tidx = [int]$s.Tag
            $script:tabs.RemoveAt($tidx)
            if ($script:activeTabIdx -ge $script:tabs.Count) { $script:activeTabIdx = $script:tabs.Count - 1 }
            Switch-Tab
        })
        $xBtn.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::FromArgb(255,90,90) })
        $xBtn.Add_MouseLeave({ $this.ForeColor = [System.Drawing.Color]::FromArgb(130,130,130) })

        $pnl.Controls.AddRange(@($lbl, $xBtn))
        [void]$script:tabStrip.Controls.Add($pnl)
    }

    # [+] new tab button
    $addBtn = New-Object System.Windows.Forms.Label -Property @{
        Text=" + "; Width=34; Height=30
        ForeColor=[System.Drawing.Color]::FromArgb(150,150,150)
        BackColor=[System.Drawing.Color]::FromArgb(38,38,38)
        Font=$boldFont; TextAlign="MiddleCenter"; Cursor="Hand"
        Margin=New-Object System.Windows.Forms.Padding(6,2,0,0)
    }
    $addBtn.Add_Click({
        $n = $script:tabs.Count + 1
        $script:tabs.Add((New-TabData "Tab $n"))
        $script:activeTabIdx = $script:tabs.Count - 1
        Switch-Tab
    })
    $addBtn.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::White })
    $addBtn.Add_MouseLeave({ $this.ForeColor = [System.Drawing.Color]::FromArgb(150,150,150) })
    [void]$script:tabStrip.Controls.Add($addBtn)

    $script:tabStrip.ResumeLayout()
}

function Switch-Tab {
    $t = Get-ActiveTab
    if ($null -eq $t) { return }
    $script:editorPanel.Controls.Clear()
    $script:logPanel.Controls.Clear()
    $script:editorPanel.Controls.Add($t.CmdBox)
    $script:logPanel.Controls.Add($t.LogBox)
    Refresh-TabStrip
    Update-StatusBar
    Apply-ThemeToTab $t
}

function Apply-ThemeToTab($t) {
    $sw = [System.Drawing.Color]::FromArgb(240,240,240)
    if ($script:isDarkMode) {
        $t.CmdBox.BackColor = [System.Drawing.Color]::FromArgb(45,45,45);  $t.CmdBox.ForeColor = $sw
        $t.LogBox.BackColor = [System.Drawing.Color]::FromArgb(35,35,35);  $t.LogBox.ForeColor = $sw
    } else {
        $t.CmdBox.BackColor = [System.Drawing.Color]::FromArgb(255,251,230); $t.CmdBox.ForeColor = [System.Drawing.Color]::Black
        $t.LogBox.BackColor = [System.Drawing.Color]::FromArgb(232,245,233); $t.LogBox.ForeColor = [System.Drawing.Color]::Black
    }
}

# ---------------------------------------------------------------------------
# 5. THEME
# ---------------------------------------------------------------------------
function Set-Theme {
    $sw = [System.Drawing.Color]::FromArgb(240,240,240)
    if ($script:isDarkMode) {
        $form.BackColor               = [System.Drawing.Color]::FromArgb(87,87,87)
        $btnPanel.BackColor           = [System.Drawing.Color]::FromArgb(60,60,60)
        $script:tabStripPanel.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
        $script:tabStrip.BackColor    = [System.Drawing.Color]::FromArgb(30,30,30)
        $hintTree.BackColor           = [System.Drawing.Color]::FromArgb(50,50,50)
        $hintTree.ForeColor           = $sw
        $hintTree.LineColor           = [System.Drawing.Color]::FromArgb(100,100,100)
        $hintSearch.BackColor         = [System.Drawing.Color]::FromArgb(70,70,70); $hintSearch.ForeColor = $sw
        $searchBox.BackColor          = [System.Drawing.Color]::FromArgb(70,70,70); $searchBox.ForeColor  = $sw
        $lblLogSearch.ForeColor       = $sw
        $chkHighlight.ForeColor       = $sw
        $chkTimestamps.ForeColor      = $sw
        $hintToolbar.BackColor        = [System.Drawing.Color]::FromArgb(45,45,45)
        $btnExpandAll.BackColor       = [System.Drawing.Color]::FromArgb(60,60,60)
        $btnExpandAll.ForeColor       = [System.Drawing.Color]::FromArgb(200,200,200)
        $btnCollapseAll.BackColor     = [System.Drawing.Color]::FromArgb(50,50,50)
        $btnCollapseAll.ForeColor     = [System.Drawing.Color]::FromArgb(200,200,200)
        $btnReloadHints.BackColor     = [System.Drawing.Color]::FromArgb(45,65,45)
        $btnReloadHints.ForeColor     = [System.Drawing.Color]::FromArgb(160,220,160)
        $script:statusPanel.BackColor = [System.Drawing.Color]::FromArgb(28,28,28)
        $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(140,140,140)
    } else {
        $form.BackColor               = [System.Drawing.Color]::WhiteSmoke
        $btnPanel.BackColor           = [System.Drawing.Color]::WhiteSmoke
        $script:tabStripPanel.BackColor = [System.Drawing.Color]::FromArgb(210,210,210)
        $script:tabStrip.BackColor    = [System.Drawing.Color]::FromArgb(210,210,210)
        $hintTree.BackColor           = [System.Drawing.Color]::White
        $hintTree.ForeColor           = [System.Drawing.Color]::Black
        $hintTree.LineColor           = [System.Drawing.Color]::Gray
        $hintSearch.BackColor         = [System.Drawing.Color]::FromArgb(232,244,220); $hintSearch.ForeColor = [System.Drawing.Color]::Black
        $searchBox.BackColor          = [System.Drawing.Color]::White; $searchBox.ForeColor = [System.Drawing.Color]::Black
        $lblLogSearch.ForeColor       = [System.Drawing.Color]::Black
        $chkHighlight.ForeColor       = [System.Drawing.Color]::Black
        $chkTimestamps.ForeColor      = [System.Drawing.Color]::Black
        $hintToolbar.BackColor        = [System.Drawing.Color]::FromArgb(220,220,220)
        $btnExpandAll.BackColor       = [System.Drawing.Color]::FromArgb(230,230,230); $btnExpandAll.ForeColor   = [System.Drawing.Color]::Black
        $btnCollapseAll.BackColor     = [System.Drawing.Color]::FromArgb(210,210,210); $btnCollapseAll.ForeColor = [System.Drawing.Color]::Black
        $btnReloadHints.BackColor     = [System.Drawing.Color]::FromArgb(200,235,200); $btnReloadHints.ForeColor = [System.Drawing.Color]::FromArgb(0,100,0)
        $script:statusPanel.BackColor = [System.Drawing.Color]::FromArgb(220,220,220)
        $script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(80,80,80)
    }
    foreach ($t in $script:tabs) { Apply-ThemeToTab $t }
    Refresh-TabStrip
}

# ---------------------------------------------------------------------------
# 6. DETACH LOG
# ---------------------------------------------------------------------------
function Show-LogDetached {
    $lb = Get-ActiveLogBox; if ($null -eq $lb) { return }
    $tabName = (Get-ActiveTab).Name
    $df = New-Object System.Windows.Forms.Form -Property @{
        Text="Quas - Log: $tabName"; Size="1000,800"
        StartPosition="CenterScreen"; BackColor=$lb.BackColor
    }
    $ps  = New-Object System.Windows.Forms.Panel -Property @{ Dock="Top"; Height=45; BackColor=$btnPanel.BackColor }
    $lsl = New-Object System.Windows.Forms.Label -Property @{ Text="Search Log:"; Left=10; Top=14; Width=80; ForeColor=$lblLogSearch.ForeColor }
    $dsb = New-Object System.Windows.Forms.TextBox -Property @{ Left=95; Top=10; Width=350; Font=$uiFont; BackColor=$searchBox.BackColor; ForeColor=$searchBox.ForeColor }
    $dab = New-Object System.Windows.Forms.RichTextBox -Property @{ Dock="Fill"; ReadOnly=$true; BackColor=$lb.BackColor; ForeColor=$lb.ForeColor; Font=$font; BorderStyle="None" }
    $dsb.Tag = $dab
    $dsb.Add_TextChanged({
        $box=$this.Tag; $q=$this.Text; if($null -eq $box){return}
        $st=$box.SelectionStart; $box.SelectAll()
        $box.SelectionBackColor=$box.BackColor
        $box.SelectionColor=if($script:isDarkMode){[System.Drawing.Color]::White}else{[System.Drawing.Color]::Black}
        if($q.Length -ge 3){
            $p=0
            while(($p=$box.Find($q,$p,[System.Windows.Forms.RichTextBoxFinds]::None)) -ge 0){
                $box.SelectionBackColor=$script:highlightColor; $box.SelectionColor=[System.Drawing.Color]::Black; $p+=$q.Length
            }
        }
        $box.Select($st,0); $box.SelectionBackColor=$box.BackColor
    })
    $ps.Controls.AddRange(@($lsl,$dsb)); $df.Controls.AddRange(@($dab,$ps))
    $dab.Text=$lb.Text; $dab.SelectionStart=$dab.Text.Length; $dab.ScrollToCaret()
    $df.Show()
}


# ---------------------------------------------------------------------------
# 7. HELP  (rich, colorized, with launch examples and GitHub link)
# ---------------------------------------------------------------------------
function Show-QuasHelp {
    $hf = New-Object System.Windows.Forms.Form -Property @{
        Text="Quas GUI Shell v5.0.3 | Reference Manual"
        Size="920,980"; StartPosition="CenterParent"
        BackColor=[System.Drawing.Color]::FromArgb(22,22,30)
        MinimizeBox=$false; MaximizeBox=$false
    }

    # Fonts
    $fTitle  = New-Object System.Drawing.Font("Consolas",  20, [System.Drawing.FontStyle]::Bold)
    $fSub    = New-Object System.Drawing.Font("Segoe UI",   9)
    $fH1     = New-Object System.Drawing.Font("Segoe UI",  13, [System.Drawing.FontStyle]::Bold)
    $fH2     = New-Object System.Drawing.Font("Segoe UI",  10, [System.Drawing.FontStyle]::Bold)
    $fBody   = New-Object System.Drawing.Font("Segoe UI",  10)
    $fCode   = New-Object System.Drawing.Font("Consolas",   9)
    $fFooter = New-Object System.Drawing.Font("Segoe UI",   9, [System.Drawing.FontStyle]::Underline)

    # Colors
    $cBg      = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $cTitle   = [System.Drawing.Color]::FromArgb(130, 190, 255)
    $cH1      = [System.Drawing.Color]::FromArgb(100, 220, 180)
    $cH2      = [System.Drawing.Color]::FromArgb(190, 150, 255)
    $cBody    = [System.Drawing.Color]::FromArgb(210, 210, 210)
    $cCode    = [System.Drawing.Color]::FromArgb(255, 220, 100)
    $cDanger  = [System.Drawing.Color]::FromArgb(255,  90,  90)
    $cCaution = [System.Drawing.Color]::FromArgb(255, 210,  60)
    $cOk      = [System.Drawing.Color]::FromArgb(120, 220, 120)
    $cGray    = [System.Drawing.Color]::FromArgb(130, 130, 140)
    $cLink    = [System.Drawing.Color]::FromArgb(100, 180, 255)
    $cSep     = [System.Drawing.Color]::FromArgb(60,  60,  75)

    $ht = New-Object System.Windows.Forms.RichTextBox -Property @{
        Dock="Fill"; ReadOnly=$true; Font=$fBody
        BackColor=$cBg; ForeColor=$cBody
        BorderStyle="None"; ScrollBars="Vertical"
        Padding=New-Object System.Windows.Forms.Padding(0)
        DetectUrls=$false
    }

    # Helper functions
    function W($text, $font, $color) {
        $ht.SelectionFont  = $font
        $ht.SelectionColor = $color
        $ht.AppendText($text)
    }
    function WL($text, $font, $color) { W ($text + "`n") $font $color }
    function Sep {
        $ht.SelectionFont  = $fBody
        $ht.SelectionColor = $cSep
        $ht.AppendText("`n" + ("_" * 72) + "`n`n")
    }
    function H1($text) {
        $ht.SelectionFont  = $fH1
        $ht.SelectionColor = $cH1
        $ht.AppendText("`n  " + $text + "`n`n")
    }
    function H2($text) {
        $ht.SelectionFont  = $fH2
        $ht.SelectionColor = $cH2
        $ht.AppendText("  " + $text + "`n")
    }
    function B($line)  { W "    - " $fBody $cGray;  WL $line $fBody $cBody }
    function Code($line) { WL ("    " + $line) $fCode $cCode }
    function Note($label,$text) {
        W ("    " + $label + " ") $fH2 $cCaution
        WL $text $fBody $cBody
    }

    # ---- HEADER ----
    $ht.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
    WL "" $fBody $cBody
    WL "Quas GUI Shell v5.0.3" $fTitle $cTitle
    WL "Advanced ADB and Command Interface Manager" $fSub $cGray
    WL "created by Varset & Gemini Dev" $fSub $cGray
    WL "" $fBody $cBody
    $ht.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Left

    Sep

    # ---- 1. LAUNCH ----
    H1 "1.  LAUNCH AND PARAMETERS"
    H2 "Basic launch (from PowerShell or CMD):"
    Code "powershell -File QuasGUIShell.ps1"
    Code "powershell -File QuasGUIShell.ps1 -ToolsPath `"C:\ADB`""
    WL "" $fBody $cBody
    H2 "Parameters:"
    B "-ToolsPath <path>    Folder containing adb.exe, fastboot.exe, etc."
    B "                     Prepended to PATH for the session. Default: empty."
    WL "" $fBody $cBody
    H2 "Typical launch inside Quas EXE bundle:"
    Code "powershell -NoProfile -ExecutionPolicy Bypass -File `"%SCRIPT%`" -ToolsPath `"%TOOLS%`""
    Note "NOTE:" "When run from a packed EXE, the script unpacks to %TEMP%. Settings are"
    W "           " $fBody $cBody
    WL "read from the folder next to the EXE, not from %TEMP%." $fBody $cBody
    WL "" $fBody $cBody

    Sep

    # ---- 2. TABS ----
    H1 "2.  TABS"
    B "[+] button or Ctrl+T    Create a new tab."
    B "[x] button or Ctrl+W    Close the active tab (minimum one tab stays)."
    B "Click tab name          Switch to that tab."
    B "Double-click tab name   Rename the tab (InputBox prompt)."
    B "Ctrl+Tab                Cycle to the next tab."
    WL "" $fBody $cBody
    H2 "Each tab is fully independent:"
    B "Own editor buffer (code/commands)."
    B "Own log history (output of all executions)."
    B "Switching tabs instantly swaps both panels."
    WL "" $fBody $cBody

    Sep

    # ---- 3. EDITOR ----
    H1 "3.  EDITOR AND EXECUTION"
    H2 "Writing commands:"
    B "Type or paste any commands, one per line."
    B "Lines starting with # are NOT skipped - they execute as-is."
    B "Blank lines are skipped automatically."
    WL "" $fBody $cBody
    H2 "Running:"
    B "F5 or [Run (F5)]    Execute all lines top to bottom."
    B "[STOP]              Abort the queue after the current command finishes."
    B "                    Shows BUSY (blue) while a command is running."
    B "[Paste]             Append clipboard text to the editor."
    B "[Clear Code] + [U]  Clear editor / restore last cleared content."
    B "Ctrl+A              Select all text in the editor."
    WL "" $fBody $cBody
    H2 "Timeout:"
    B "Each command has a 20-second hard timeout."
    B "If exceeded, the process is killed and [TIMEOUT] appears in the log."
    B "Interactive commands should use Smart Interceptor (see section 4)."
    WL "" $fBody $cBody
    H2 "Example - run a quick device info block:"
    Code "adb devices -l"
    Code "adb shell getprop ro.product.model"
    Code "adb shell getprop ro.build.version.release"
    Code "adb shell uptime"
    WL "" $fBody $cBody

    Sep

    # ---- 4. INTERCEPTOR ----
    H1 "4.  SMART INTERCEPTOR"
    WL "  Some commands are interactive or produce infinite output. Running them" $fBody $cBody
    WL "  inside the GUI log would freeze the interface. The interceptor detects" $fBody $cBody
    WL "  these automatically and launches them in an external console instead." $fBody $cBody
    WL "" $fBody $cBody
    H2 "Intercepted automatically:"
    B "Shells:   cmd, powershell, pwsh, adb shell (bare), ftp, ssh, nslookup, python, node"
    B "Streams:  adb shell top, ping -t, logcat (without -d flag), watch, monitor"
    B "Heavy:    scrcpy, diskpart, telnet"
    WL "" $fBody $cBody
    H2 "What happens:"
    B "A [REDIRECT] message appears in the log."
    B "cmd.exe /k opens for most commands (stays open after finish)."
    B "cmd.exe /c opens for adb and scrcpy (closes after finish)."
    B "powershell -NoExit opens for powershell/pwsh commands."
    WL "" $fBody $cBody
    H2 "Example - these lines trigger redirect:"
    Code "adb shell"
    Code "adb logcat"
    Code "ping -t 8.8.8.8"
    Code "powershell"
    WL "" $fBody $cBody

    Sep

    # ---- 5. LOG ----
    H1 "5.  LOG PANEL"
    B "[Copy Log]      Copy entire active log to clipboard."
    B "[Save Log]      Export active log to a UTF-8 .txt file (SaveDialog)."
    B "[Detach Log]    Open active log in a separate resizable window with search."
    B "[Clear Log] + [U]  Clear log / restore last cleared content."
    B "[Timestamps]    Toggle a grey 'Run at HH:mm:ss' header before each run block."
    WL "" $fBody $cBody
    H2 "Log color coding:"
    W "    " $fBody $cBody;  W "Cyan / Blue   " $fBody $cTitle;   WL "> command line echo" $fBody $cBody
    W "    " $fBody $cBody;  W "White         " $fBody $cBody;     WL "Normal stdout output" $fBody $cBody
    W "    " $fBody $cBody;  W "Red           " $fBody $cDanger;   WL "Stderr output (errors)" $fBody $cBody
    W "    " $fBody $cBody;  W "Orange        " $fBody $cCaution;  WL "[REDIRECT] and [TIMEOUT] messages" $fBody $cBody
    W "    " $fBody $cBody;  W "Grey          " $fBody $cGray;     WL "Timestamp headers and advice" $fBody $cBody
    WL "" $fBody $cBody

    Sep

    # ---- 6. LOG SEARCH ----
    H1 "6.  LOG SEARCH"
    B "Always visible in the bottom bar - no toggle needed."
    B "Type 3+ characters to highlight all matches in yellow."
    B "[Highlight] checkbox    Enable/disable the yellow soft-vision highlight."
    B "[Extract to Notepad]    Pull all matching lines into a temp .txt in Notepad."
    B "                        Useful for filtering large logs by keyword."
    WL "" $fBody $cBody
    H2 "Example workflow:"
    B "Run 10 adb commands."
    B "Type 'error' in the search box."
    B "All error lines glow yellow."
    B "Click Extract to Notepad for a clean error-only report."
    WL "" $fBody $cBody

    Sep

    # ---- 7. HINTS ----
    H1 "7.  HINTS PANEL  (right sidebar)"
    B "Shows commands from hints.txt grouped into collapsible categories."
    B "Double-click any command to insert it into the active editor."
    B "Single-click a category header to expand / collapse it."
    B "[+ Expand] / [- Collapse]   Toggle all categories at once."
    B "[Reload]   Re-read hints.txt without restarting - edit live."
    B "Filter box at the top searches across all categories instantly."
    B "[Hints On/Off]   Show or hide the entire sidebar."
    WL "" $fBody $cBody
    H2 "Command color coding in hints:"
    W "    " $fBody $cBody;  W "! prefix  " $fCode $cDanger;   WL "  DANGER - irreversible (delete, wipe, force-reboot)" $fBody $cBody
    W "    " $fBody $cBody;  W "~ prefix  " $fCode $cCaution;  WL "  CAUTION - changes settings or state" $fBody $cBody
    W "    " $fBody $cBody;  W "no prefix " $fCode $cOk;       WL "  Safe - read-only or informational" $fBody $cBody
    WL "" $fBody $cBody
    H2 "hints.txt format:"
    Code "[ Section Name ]"
    Code "adb devices"
    Code "~adb shell setprop debug.oculus.cpuLevel 4"
    Code "!adb shell rm -rf /data/local/tmp/*"
    Code ""
    Code "# This is a comment - skipped"
    Code "# --- Legacy Section ---  (auto-detected)"
    WL "" $fBody $cBody
    B "File location: same folder as script, or Source subfolder."
    WL "" $fBody $cBody

    Sep

    # ---- 8. SHORTCUTS ----
    H1 "8.  KEYBOARD SHORTCUTS"
    $shortcuts = @(
        @("F5",           "Run all commands in the active editor"),
        @("Ctrl+A",       "Select all text in the active editor"),
        @("Ctrl+T",       "New tab"),
        @("Ctrl+W",       "Close active tab"),
        @("Ctrl+Tab",     "Switch to next tab")
    )
    foreach ($sc in $shortcuts) {
        W ("    ") $fBody $cBody
        W ([string]$sc[0]).PadRight(16) $fCode $cCode
        WL ([string]$sc[1]) $fBody $cBody
    }
    WL "" $fBody $cBody

    Sep

    # ---- 9. THEME ----
    H1 "9.  THEME AND LAYOUT"
    B "[Theme]          Toggle Dark / Light visual mode."
    B "[Hints On/Off]   Show or hide the right sidebar."
    B "Splitter bar     Drag the horizontal divider to resize editor vs log."
    B "Vertical splitter  Drag to resize editor vs hints panel width."
    WL "" $fBody $cBody

    Sep

    # ---- FOOTER ----
    $ht.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
    WL "" $fBody $cBody
    WL "Online documentation and source code:" $fSub $cGray
    WL "" $fBody $cBody

    # Clickable link label (opens browser)
    $linkPanel = New-Object System.Windows.Forms.Panel -Property @{
        Height=28; Dock="Bottom"; BackColor=$cBg
    }
    $lnk = New-Object System.Windows.Forms.LinkLabel -Property @{
        Text="https://github.com/Varsett/QuasGUIshell"
        Dock="Fill"; Font=$fFooter; TextAlign="MiddleCenter"
        BackColor=$cBg; LinkColor=$cLink; ActiveLinkColor=[System.Drawing.Color]::White
    }
    $lnk.Add_LinkClicked({ Start-Process "https://github.com/Varsett/QuasGUIshell" })
    $linkPanel.Controls.Add($lnk)

    WL "Created by Varset and Gemini Dev  |  Refactored 2026" $fSub $cGray
    WL "" $fBody $cBody
    $ht.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Left

    # Assemble form: link at bottom, rich text fills rest
    # TableLayoutPanel so nothing overlaps
    $tbl = New-Object System.Windows.Forms.TableLayoutPanel
    $tbl.Dock = "Fill"
    $tbl.ColumnCount = 1; $tbl.RowCount = 2
    $tbl.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$tbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
    [void]$tbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))
    [void]$tbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 30)))
    $tbl.Controls.Add($ht, 0, 0)
    $tbl.Controls.Add($linkPanel, 0, 1)
    $hf.Controls.Add($tbl)

    $ht.SelectionStart = 0; $ht.ScrollToCaret()
    $null = $hf.ShowDialog()
}

# ---------------------------------------------------------------------------
# 8. RUN ACTION
# ---------------------------------------------------------------------------
$runAction = {
    $t = Get-ActiveTab; if ($null -eq $t) { return }
    $cmdBox = $t.CmdBox
    $logBox = $t.LogBox

    $script:isStopping = $false
    $shells = @("cmd","powershell","pwsh","nslookup","python","node","ssh","telnet","diskpart","scrcpy","ftp")

    if ($script:showTimestamps) {
        $ts = (Get-Date).ToString("HH:mm:ss")
        $logBox.SelectionColor = [System.Drawing.Color]::FromArgb(120,120,120)
        $logBox.AppendText("`n--- Run at $ts ---`n")
    }

    foreach ($line in $cmdBox.Lines) {
        $trimmed   = $line.Trim()
        $cleanLine = $trimmed.ToLower()
        if ($script:isStopping -or [string]::IsNullOrWhiteSpace($cleanLine)) { continue }

        $finalCmd      = $trimmed
        $needsRedirect = $false

        foreach ($sh in $shells) {
            if ($cleanLine -eq $sh -or $cleanLine.StartsWith("$sh ")) { $needsRedirect = $true; break }
        }
        if (-not $needsRedirect -and $cleanLine.StartsWith("adb")) {
            if ($cleanLine -eq "adb shell" -or ($cleanLine -match "top|ping -t|watch |monitor")) { $needsRedirect = $true }
            elseif ($cleanLine -match "logcat" -and -not $cleanLine.Contains("-d")) { $needsRedirect = $true }
        }

        if ($needsRedirect) {
            $logBox.SelectionColor = [System.Drawing.Color]::Orange
            $logBox.AppendText("`n[REDIRECT] External console: '$trimmed'`n")
            $proc     = if ($cleanLine -match "powershell|pwsh") { "powershell.exe" } else { "cmd.exe" }
            $waitFlag = if ($cleanLine.StartsWith("scrcpy") -or $cleanLine.StartsWith("adb")) { "/c" } else { "/k" }
            $procArgs = if ($proc -eq "powershell.exe") { "-NoExit", "-Command", "& { $finalCmd }" } else { "$waitFlag $finalCmd" }
            Start-Process $proc -ArgumentList $procArgs
            continue
        }

        $logBox.SelectionColor = if ($script:isDarkMode) { [System.Drawing.Color]::Cyan } else { [System.Drawing.Color]::Blue }
        $logBox.AppendText("`n> $line`n")

        $btnStop.Text = "BUSY"; $btnStop.BackColor = [System.Drawing.Color]::DeepSkyBlue
        $btnRun.Enabled = $false
        Update-StatusBar
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $si = New-Object System.Diagnostics.ProcessStartInfo
            $si.FileName               = "cmd.exe"
            $si.Arguments              = "/c $finalCmd"
            $si.RedirectStandardOutput = $true
            $si.RedirectStandardError  = $true
            $si.UseShellExecute        = $false
            $si.CreateNoWindow         = $true
            $si.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(866)
            $si.StandardErrorEncoding  = [System.Text.Encoding]::GetEncoding(866)

            $p        = [System.Diagnostics.Process]::Start($si)
            $outTask  = $p.StandardOutput.ReadToEndAsync()
            $errTask  = $p.StandardError.ReadToEndAsync()
            $finished = $p.WaitForExit(20000)
            if (-not $finished) { try { $p.Kill() } catch {} }

            $out = $outTask.Result; $err = $errTask.Result
            if ($out) {
                $logBox.SelectionColor = if ($script:isDarkMode) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
                $logBox.AppendText($out)
            }
            if ($err) { $logBox.SelectionColor = [System.Drawing.Color]::Red; $logBox.AppendText($err) }
            if (-not $finished) {
                $logBox.SelectionColor = [System.Drawing.Color]::Orange
                $logBox.AppendText("`n[TIMEOUT] Process terminated after 20s.`n")
                $logBox.SelectionColor = [System.Drawing.Color]::Gray
                $logBox.AppendText("ADVICE: Interactive command - run in a real CMD/PowerShell.`n")
            }
        } catch {
            $logBox.SelectionColor = [System.Drawing.Color]::Red
            $logBox.AppendText("`nError: $($_.Exception.Message)")
        } finally {
            $btnStop.Text = "STOP"; $btnStop.BackColor = [System.Drawing.Color]::LightPink
            $btnRun.Enabled = $true; $logBox.ScrollToCaret()
            Update-StatusBar
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}



# ---------------------------------------------------------------------------
# 9. UI LAYOUT  (TableLayoutPanel - no Dock magic needed)
# ---------------------------------------------------------------------------
# Form contains a single TableLayoutPanel with 3 rows:
#   Row 0 - fixed 34px  - tab strip
#   Row 1 - fill 100%   - main split (editor left, log right column, log bottom)
#   Row 2 - fixed 117px - button panel + status bar

$form = New-Object System.Windows.Forms.Form
$form.Text          = "Quas GUI Shell v5.0.3"
$form.Size          = "1300,980"
$form.StartPosition = "CenterScreen"
$form.KeyPreview    = $true

# Root table: 1 column, 3 rows
$rootTable = New-Object System.Windows.Forms.TableLayoutPanel
$rootTable.Dock        = "Fill"
$rootTable.ColumnCount = 1
$rootTable.RowCount    = 3
$rootTable.Padding     = New-Object System.Windows.Forms.Padding(0)
$rootTable.Margin      = New-Object System.Windows.Forms.Padding(0)
[void]$rootTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
[void]$rootTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 34)))   # tab strip
[void]$rootTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent",  100)))  # content
[void]$rootTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 117)))  # buttons

# ---- Row 0: Tab strip ----
$script:tabStripPanel = New-Object System.Windows.Forms.Panel
$script:tabStripPanel.Dock      = "Fill"
$script:tabStripPanel.Margin    = New-Object System.Windows.Forms.Padding(0)
$script:tabStripPanel.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)

$script:tabStrip = New-Object System.Windows.Forms.FlowLayoutPanel
$script:tabStrip.Dock          = "Fill"
$script:tabStrip.FlowDirection = "LeftToRight"
$script:tabStrip.WrapContents  = $false
$script:tabStrip.BackColor     = [System.Drawing.Color]::FromArgb(30,30,30)
$script:tabStrip.Padding       = New-Object System.Windows.Forms.Padding(2,2,0,0)
$script:tabStripPanel.Controls.Add($script:tabStrip)
$rootTable.Controls.Add($script:tabStripPanel, 0, 0)

# ---- Row 1: Main content (SplitContainer) ----
$mainSplit = New-Object System.Windows.Forms.SplitContainer
$mainSplit.Dock        = "Fill"
$mainSplit.Orientation = "Horizontal"
$mainSplit.Margin      = New-Object System.Windows.Forms.Padding(0)

$topSplit = New-Object System.Windows.Forms.SplitContainer
$topSplit.Dock        = "Fill"
$topSplit.Orientation = "Vertical"
$topSplit.FixedPanel   = "Panel2"
$topSplit.Margin       = New-Object System.Windows.Forms.Padding(0)

$script:editorPanel = New-Object System.Windows.Forms.Panel
$script:editorPanel.Dock   = "Fill"
$script:editorPanel.Margin = New-Object System.Windows.Forms.Padding(0)

$script:logPanel = New-Object System.Windows.Forms.Panel
$script:logPanel.Dock   = "Fill"
$script:logPanel.Margin = New-Object System.Windows.Forms.Padding(0)

# Hints column - use TableLayoutPanel inside Panel2 to avoid Dock stacking issues
$hintsTable = New-Object System.Windows.Forms.TableLayoutPanel
$hintsTable.Dock        = "Fill"
$hintsTable.ColumnCount = 1
$hintsTable.RowCount    = 3
$hintsTable.Padding     = New-Object System.Windows.Forms.Padding(0)
$hintsTable.Margin      = New-Object System.Windows.Forms.Padding(0)
[void]$hintsTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
[void]$hintsTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 28)))  # filter box
[void]$hintsTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 28)))  # toolbar
[void]$hintsTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent",  100))) # tree

$hintSearch = New-Object System.Windows.Forms.TextBox
$hintSearch.Dock      = "Fill"
$hintSearch.Font      = $uiFont
$hintSearch.Margin    = New-Object System.Windows.Forms.Padding(0)
$hintSearch.BackColor = [System.Drawing.Color]::FromArgb(232,244,220)

$hintToolbar = New-Object System.Windows.Forms.Panel
$hintToolbar.Dock   = "Fill"
$hintToolbar.Margin = New-Object System.Windows.Forms.Padding(0)

# Use a TableLayoutPanel inside toolbar so all 3 buttons fill width equally
$hintBtnTable = New-Object System.Windows.Forms.TableLayoutPanel
$hintBtnTable.Dock        = "Fill"
$hintBtnTable.ColumnCount = 3
$hintBtnTable.RowCount    = 1
$hintBtnTable.Padding     = New-Object System.Windows.Forms.Padding(0)
$hintBtnTable.Margin      = New-Object System.Windows.Forms.Padding(0)
[void]$hintBtnTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 33.3)))
[void]$hintBtnTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 33.3)))
[void]$hintBtnTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 33.4)))
[void]$hintBtnTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))

$btnExpandAll = New-Object System.Windows.Forms.Button
$btnExpandAll.Text      = "+ Expand"
$btnExpandAll.Dock      = "Fill"
$btnExpandAll.Margin    = New-Object System.Windows.Forms.Padding(0)
$btnExpandAll.FlatStyle = "Flat"; $btnExpandAll.Font = $uiFont
$btnExpandAll.BackColor = [System.Drawing.Color]::FromArgb(60,60,60)
$btnExpandAll.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)

$btnCollapseAll = New-Object System.Windows.Forms.Button
$btnCollapseAll.Text      = "- Collapse"
$btnCollapseAll.Dock      = "Fill"
$btnCollapseAll.Margin    = New-Object System.Windows.Forms.Padding(0)
$btnCollapseAll.FlatStyle = "Flat"; $btnCollapseAll.Font = $uiFont
$btnCollapseAll.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnCollapseAll.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)

$btnReloadHints = New-Object System.Windows.Forms.Button
$btnReloadHints.Text      = "Reload"
$btnReloadHints.Dock      = "Fill"
$btnReloadHints.Margin    = New-Object System.Windows.Forms.Padding(0)
$btnReloadHints.FlatStyle = "Flat"; $btnReloadHints.Font = $uiFont
$btnReloadHints.BackColor = [System.Drawing.Color]::FromArgb(45,65,45)
$btnReloadHints.ForeColor = [System.Drawing.Color]::FromArgb(160,220,160)

$hintBtnTable.Controls.Add($btnExpandAll,   0, 0)
$hintBtnTable.Controls.Add($btnCollapseAll, 1, 0)
$hintBtnTable.Controls.Add($btnReloadHints, 2, 0)
$hintToolbar.Controls.Add($hintBtnTable)

$hintTree = New-Object System.Windows.Forms.TreeView
$hintTree.Dock             = "Fill"
$hintTree.Font             = $uiFont
$hintTree.ShowLines        = $true
$hintTree.ShowPlusMinus    = $true
$hintTree.ShowRootLines    = $true
$hintTree.HideSelection    = $false
$hintTree.BorderStyle      = "None"
$hintTree.ShowNodeToolTips = $true
$hintTree.Scrollable       = $true
$hintTree.Margin           = New-Object System.Windows.Forms.Padding(0)
Populate-HintTree $hintTree ""

$hintsTable.Controls.Add($hintSearch,  0, 0)
$hintsTable.Controls.Add($hintToolbar, 0, 1)
$hintsTable.Controls.Add($hintTree,    0, 2)

$topSplit.Panel1.Controls.Add($script:editorPanel)
$topSplit.Panel2.Controls.Add($hintsTable)
$mainSplit.Panel1.Controls.Add($topSplit)
$mainSplit.Panel2.Controls.Add($script:logPanel)
$rootTable.Controls.Add($mainSplit, 0, 1)

# ---- Row 2: Button panel ----
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Dock      = "Fill"
$btnPanel.Margin    = New-Object System.Windows.Forms.Padding(0)
$btnPanel.BackColor = [System.Drawing.Color]::WhiteSmoke

# Status bar at bottom of btnPanel
$script:statusPanel = New-Object System.Windows.Forms.Panel
$script:statusPanel.Dock      = "Bottom"
$script:statusPanel.Height    = 22
$script:statusPanel.BackColor = [System.Drawing.Color]::FromArgb(28,28,28)
$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Dock      = "Fill"
$script:statusLabel.Font      = $uiFont
$script:statusLabel.TextAlign = "MiddleLeft"
$script:statusLabel.Padding   = New-Object System.Windows.Forms.Padding(8,0,0,0)
$script:statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(140,140,140)
$script:statusPanel.Controls.Add($script:statusLabel)
$btnPanel.Controls.Add($script:statusPanel)

function Create-Btn($txt,$x,$y,$w=85,$clr="Control") {
    New-Object System.Windows.Forms.Button -Property @{
        Text=$txt; Left=$x; Top=$y; Width=$w; Height=30
        FlatStyle="Flat"; BackColor=[System.Drawing.Color]::$clr
    }
}
# Row 1 - main buttons (Top=10)
$btnRun         = Create-Btn "Run (F5)"      10  10  95  "LightGreen"
$btnStop        = Create-Btn "STOP"         110  10  70  "LightPink"
$btnPaste       = Create-Btn "Paste"        210  10  70  "White"
$btnClearCmd    = Create-Btn "Clear Code"   285  10  90  "White"
$btnUndoCmd     = Create-Btn "U"           375  10  30  "LightGray"
$btnCopyLog     = Create-Btn "Copy Log"    440  10  85  "Lavender"
$btnSave        = Create-Btn "Save Log"    530  10  85  "Lavender"
$btnDetach      = Create-Btn "Detach Log"  620  10  85  "Lavender"
$btnClearLog    = Create-Btn "Clear Log"   740  10  85  "Lavender"
$btnUndoLog     = Create-Btn "U"          825  10  30  "LightGray"
$btnHintsToggle = Create-Btn "Hints On/Off" 875 10 100  "Azure"
$btnTheme       = Create-Btn "Theme"       980  10  75  "DarkGray"
# [?] fixed position, right-aligned via Anchor
$btnHelp        = Create-Btn "?"          1160  10  35  "LightBlue"
$btnHelp.Anchor = [System.Windows.Forms.AnchorStyles]"Top,Right"

# Row 2 - always-visible log search bar (Top=50)
# Label "Log Search:"
$lblLogSearch = New-Object System.Windows.Forms.Label -Property @{
    Text="Log Search:"; Left=10; Top=54; Width=80; Height=22
    TextAlign="MiddleLeft"
}
# Search input
$searchBox = New-Object System.Windows.Forms.TextBox -Property @{
    Left=92; Top=52; Width=260; Height=22; Font=$uiFont
}
# Highlight checkbox
$chkHighlight = New-Object System.Windows.Forms.CheckBox -Property @{
    Text="Highlight"; Left=360; Top=52; Width=90; Checked=$true
}
# Timestamps checkbox
$chkTimestamps = New-Object System.Windows.Forms.CheckBox -Property @{
    Text="Timestamps"; Left=455; Top=52; Width=105; Checked=$true
}
# "Extract to Notepad" - renamed from Deep Sync, right-aligned under Detach Log
$btnDeep = New-Object System.Windows.Forms.Button -Property @{
    Text="Extract to Notepad"; Left=585; Top=48; Width=120; Height=30
    FlatStyle="Flat"; BackColor=[System.Drawing.Color]::Beige
}

$btnPanel.Controls.AddRange(@(
    $btnRun,$btnStop,$btnPaste,$btnClearCmd,$btnUndoCmd,
    $btnCopyLog,$btnSave,$btnDetach,$btnClearLog,$btnUndoLog,
    $btnHintsToggle,$btnTheme,$btnHelp,
    $lblLogSearch,$searchBox,$chkHighlight,$chkTimestamps,$btnDeep
))
$rootTable.Controls.Add($btnPanel, 0, 2)

$form.Controls.Add($rootTable)

# ---------------------------------------------------------------------------
# 10. EVENTS
# ---------------------------------------------------------------------------
$btnRun.Add_Click($runAction)
$btnStop.Add_Click({ $script:isStopping = $true })
$btnPaste.Add_Click({ $cb=Get-ActiveCmdBox; if($cb){$cb.AppendText([System.Windows.Forms.Clipboard]::GetText())} })
$btnClearCmd.Add_Click({ $cb=Get-ActiveCmdBox; if($cb -and $cb.Text){$script:lastCodeBackup=$cb.Text;$cb.Clear()} })
$btnUndoCmd.Add_Click({ $cb=Get-ActiveCmdBox; if($cb -and $script:lastCodeBackup){$cb.Text=$script:lastCodeBackup} })
$btnClearLog.Add_Click({ $lb=Get-ActiveLogBox; if($lb -and $lb.Text){$script:lastLogBackup=$lb.Text;$lb.Clear()} })
$btnUndoLog.Add_Click({ $lb=Get-ActiveLogBox; if($lb -and $script:lastLogBackup){$lb.AppendText($script:lastLogBackup)} })
$btnCopyLog.Add_Click({ $lb=Get-ActiveLogBox; if($lb -and $lb.Text){[System.Windows.Forms.Clipboard]::SetText($lb.Text)} })
$btnSave.Add_Click({
    $lb=Get-ActiveLogBox; if(-not $lb){return}
    $sfd=New-Object System.Windows.Forms.SaveFileDialog -Property @{Filter="Text Files|*.txt";Title="Save Quas Log"}
    if($sfd.ShowDialog()-eq"OK"){$lb.Text|Out-File -FilePath $sfd.FileName -Encoding utf8}
})
$btnDetach.Add_Click({ Show-LogDetached })
$btnTheme.Add_Click({ $script:isDarkMode=-not $script:isDarkMode; Set-Theme })
$btnHintsToggle.Add_Click({ $topSplit.Panel2Collapsed=-not $topSplit.Panel2Collapsed })
$btnHelp.Add_Click({ Show-QuasHelp })
$chkTimestamps.Add_CheckedChanged({ $script:showTimestamps=$chkTimestamps.Checked })
# Log search is always visible - no toggle needed

$fnHighlight = {
    $lb=Get-ActiveLogBox; if(-not $lb){return}
    $st=$lb.SelectionStart; $lb.SelectAll()
    $lb.SelectionBackColor=$lb.BackColor
    $lb.SelectionColor=if($script:isDarkMode){[System.Drawing.Color]::White}else{[System.Drawing.Color]::Black}
    if($chkHighlight.Checked -and $searchBox.Text.Length -ge 3){
        $f=$searchBox.Text; $p=0
        while(($p=$lb.Find($f,$p,[System.Windows.Forms.RichTextBoxFinds]::None))-ge 0){
            $lb.SelectionBackColor=$script:highlightColor; $lb.SelectionColor=[System.Drawing.Color]::Black; $p+=$f.Length
        }
    }
    $lb.Select($st,0); $lb.SelectionBackColor=$lb.BackColor
}
$searchBox.Add_TextChanged($fnHighlight); $chkHighlight.Add_CheckedChanged($fnHighlight)

$btnDeep.Add_Click({
    $lb=Get-ActiveLogBox; if(-not $lb){return}
    $q=$searchBox.Text.ToLower(); if(-not $q){return}
    $res=$lb.Text -split "`n"|Where-Object{$_.ToLower().Contains($q)}
    if($res){$tmp=[System.IO.Path]::GetTempFileName()+".txt";$res.Trim()|Out-File $tmp -Encoding utf8;Start-Process notepad.exe $tmp}
})
$hintSearch.Add_TextChanged({ Populate-HintTree $hintTree $hintSearch.Text })
$btnExpandAll.Add_Click({ $hintTree.BeginUpdate();$hintTree.ExpandAll();$hintTree.EndUpdate() })
$btnCollapseAll.Add_Click({ $hintTree.BeginUpdate();$hintTree.CollapseAll();$hintTree.EndUpdate() })
$btnReloadHints.Add_Click({
    $found = Find-HintsFile
    if ($found) {
        $script:hintCategories = Parse-HintsFile $found
        Populate-HintTree $hintTree $hintSearch.Text
        $lb = Get-ActiveLogBox
        if ($lb) {
            $lb.SelectionColor = [System.Drawing.Color]::FromArgb(120,120,120)
            $lb.AppendText("`n[Hints reloaded: $found]`n")
        }
    } else {
        $lb = Get-ActiveLogBox
        if ($lb) {
            $lb.SelectionColor = [System.Drawing.Color]::FromArgb(255,90,90)
            $lb.AppendText("`n[Hints reload failed: hints.txt not found]`n")
        }
    }
})
$hintTree.Add_NodeMouseDoubleClick({
    param($s,$e)
    if($e.Node -and ($null -ne $e.Node.Tag)){
        $cb=Get-ActiveCmdBox
        if($cb){$cb.AppendText($e.Node.Tag.ToString()+"`r`n");$cb.Focus()}
    }
})

$form.Add_KeyDown({
    param($s,$e)
    if($e.KeyCode -eq "F5")  { & $runAction }
    if($e.Control -and $e.KeyCode -eq "A") { $cb=Get-ActiveCmdBox; if($cb){$cb.SelectAll()} }
    if($e.Control -and $e.KeyCode -eq "T") {
        $n=$script:tabs.Count+1
        $script:tabs.Add((New-TabData "Tab $n"))
        $script:activeTabIdx=$script:tabs.Count-1
        Switch-Tab
    }
    if($e.Control -and $e.KeyCode -eq "W") {
        if($script:tabs.Count -le 1){return}
        $script:tabs.RemoveAt($script:activeTabIdx)
        if($script:activeTabIdx -ge $script:tabs.Count){$script:activeTabIdx=$script:tabs.Count-1}
        Switch-Tab
    }
    if($e.Control -and $e.KeyCode -eq "Tab") {
        $script:activeTabIdx=($script:activeTabIdx+1) % $script:tabs.Count
        Switch-Tab
    }
})

$form.Add_Load({
    $btnHelp.Left = $btnPanel.Width - 50
    # Create first tab
    $script:tabs.Add((New-TabData "Tab 1"))
    $script:activeTabIdx = 0
    Switch-Tab
    Set-Theme
    Update-StatusBar
})

$form.Add_Shown({
    # Set splitter distances once the form has real dimensions
    $topSplit.SplitterDistance  = [int]($mainSplit.Width * 0.73)
    $mainSplit.SplitterDistance = [int]($mainSplit.Height * 0.42)
})

$form.Add_Resize({
    $btnHelp.Left = $btnPanel.Width - 50
})

$null=$form.ShowDialog()
$form.Dispose()