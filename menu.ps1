Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { "$env:USERPROFILE\Desktop\MyMenu" }
$configFile = Join-Path $scriptDir "custom_apps.json"
$settingsFile = Join-Path $scriptDir "settings.json"

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class WinCore {
    [StructLayout(LayoutKind.Sequential)]
    internal struct WindowCompositionAttributeData {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct AccentPolicy {
        public int AccentState;
        public int AccentFlags;
        public uint GradientColor;
        public int AnimationId;
    }

    [DllImport("user32.dll")]
    internal static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    public static void SetBlur(IntPtr hwnd, int state, uint color) {
        if (hwnd == IntPtr.Zero) return;
        AccentPolicy accent = new AccentPolicy();
        accent.AccentState = state;
        accent.AccentFlags = 2;
        accent.GradientColor = color;
        int size = Marshal.SizeOf(accent);
        IntPtr ptr = Marshal.AllocHGlobal(size);
        Marshal.StructureToPtr(accent, ptr, false);
        WindowCompositionAttributeData data = new WindowCompositionAttributeData();
        data.Attribute = 19;
        data.SizeOfData = size;
        data.Data = ptr;
        SetWindowCompositionAttribute(hwnd, ref data);
        Marshal.FreeHGlobal(ptr);
    }

    public static void ApplyTaskbarGlass(bool enable) {
        IntPtr tb = FindWindow("Shell_TrayWnd", null);
        if (tb != IntPtr.Zero) {
            if (enable) SetBlur(tb, 4, 0x66141418);
            else SetBlur(tb, 0, 0);
        }
    }

    public static void ApplyWindowsAlpha(bool enable, byte alpha, IntPtr skip1, IntPtr skip2) {
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            if (hWnd == skip1 || hWnd == skip2 || !IsWindowVisible(hWnd)) return true;
            StringBuilder sb = new StringBuilder(256);
            GetClassName(hWnd, sb, sb.Capacity);
            string cls = sb.ToString();
            if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Windows.UI.Core.CoreWindow") return true;
            int ex = GetWindowLong(hWnd, -20);
            if (enable) {
                if ((ex & 0x80000) == 0) SetWindowLong(hWnd, -20, ex | 0x80000);
                SetLayeredWindowAttributes(hWnd, 0, alpha, 0x2);
            } else {
                if ((ex & 0x80000) != 0) SetLayeredWindowAttributes(hWnd, 0, 255, 0x2);
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms

function U([int[]]$codes) {
    return -join ($codes | ForEach-Object { [char]$_ })
}

$global:cfg = [PSCustomObject]@{
    Opacity      = 95
    Slide        = $true
    Accent       = 0
    TaskbarGlass = $true
    WinGlass     = $false
    TopMost      = $true
}

if (Test-Path $settingsFile) {
    try {
        $loadedCfg = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($loadedCfg) {
            if ($null -ne $loadedCfg.Opacity)      { $global:cfg.Opacity      = [int]$loadedCfg.Opacity }
            if ($null -ne $loadedCfg.Slide)        { $global:cfg.Slide        = [bool]$loadedCfg.Slide }
            if ($null -ne $loadedCfg.Accent)       { $global:cfg.Accent       = [int]$loadedCfg.Accent }
            if ($null -ne $loadedCfg.TaskbarGlass) { $global:cfg.TaskbarGlass = [bool]$loadedCfg.TaskbarGlass }
            if ($null -ne $loadedCfg.WinGlass)     { $global:cfg.WinGlass     = [bool]$loadedCfg.WinGlass }
            if ($null -ne $loadedCfg.TopMost)      { $global:cfg.TopMost      = [bool]$loadedCfg.TopMost }
        }
    } catch {}
}

function Save-Settings {
    $global:cfg | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8
}

$accents = @(
    [System.Drawing.Color]::FromArgb(0, 120, 212),
    [System.Drawing.Color]::FromArgb(136, 68, 224),
    [System.Drawing.Color]::FromArgb(16, 155, 102),
    [System.Drawing.Color]::FromArgb(215, 55, 95)
)

function Get-AccentColor {
    return $accents[$global:cfg.Accent % $accents.Count]
}

function Get-RoundedPath([int]$w, [int]$h, [int]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r, $r, 180, 90)
    $path.AddArc($w - $r, 0, $r, $r, 270, 90)
    $path.AddArc($w - $r, $h - $r, $r, $r, 0, 90)
    $path.AddArc(0, $h - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-AppIcon {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 212))
    $g.FillPath($brush, (Get-RoundedPath 30 30 8))
    $bolt = [System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point(18, 5)),
        (New-Object System.Drawing.Point(9, 17)),
        (New-Object System.Drawing.Point(15, 17)),
        (New-Object System.Drawing.Point(13, 27)),
        (New-Object System.Drawing.Point(23, 14)),
        (New-Object System.Drawing.Point(17, 14))
    )
    $g.FillPolygon([System.Drawing.Brushes]::White, $bolt)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$customIcon = New-AppIcon

$f4Form = New-Object System.Windows.Forms.Form
$f4Form.Size = New-Object System.Drawing.Size(300, 320)
$f4Form.FormBorderStyle = 'None'
$f4Form.StartPosition = 'CenterScreen'
$f4Form.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 30)
$f4Form.Opacity = 0.96
$f4Form.TopMost = $true
$f4Form.ShowInTaskbar = $false
$f4Form.Region = New-Object System.Drawing.Region((Get-RoundedPath 300 320 16))

$f4Header = New-Object System.Windows.Forms.Label
$f4Header.Text = (U @(0x0421,0x0438,0x0441,0x0442,0x0435,0x043C,0x043D,0x0430,0x044F,0x0020,0x043F,0x0430,0x043D,0x0435,0x043B,0x044C))
$f4Header.ForeColor = [System.Drawing.Color]::FromArgb(120, 200, 255)
$f4Header.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$f4Header.Location = New-Object System.Drawing.Point(18, 12)
$f4Header.Size = New-Object System.Drawing.Size(264, 24)
$f4Header.Cursor = 'SizeAll'
$f4Form.Controls.Add($f4Header)

$script:f4Drag = $false
$script:f4Start = [System.Drawing.Point]::Empty
$f4Header.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $script:f4Drag = $true; $script:f4Start = $e.Location } })
$f4Header.Add_MouseMove({ param($s, $e) if ($script:f4Drag) { $f4Form.Location = New-Object System.Drawing.Point(($f4Form.Left + $e.X - $script:f4Start.X), ($f4Form.Top + $e.Y - $script:f4Start.Y)) } })
$f4Header.Add_MouseUp({ $script:f4Drag = $false })

function New-F4Button($text, $y, $color, $action) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point(18, $y)
    $btn.Size = New-Object System.Drawing.Size(264, 34)
    $btn.BackColor = $color
    $btn.ForeColor = 'White'
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = 'Hand'
    $btn.Region = New-Object System.Drawing.Region((Get-RoundedPath 264 34 8))
    $btn.Add_Click($action)
    $f4Form.Controls.Add($btn)
}

New-F4Button (U @(0x0414,0x0438,0x0441,0x043F,0x0435,0x0442,0x0447,0x0435,0x0440,0x0020,0x0437,0x0430,0x0434,0x0430,0x0447)) 46 ([System.Drawing.Color]::FromArgb(0, 120, 212)) {
    Start-Process "taskmgr.exe"
    $f4Form.Hide()
}
New-F4Button (U @(0x041C,0x043E,0x043D,0x0438,0x0442,0x043E,0x0440,0x0020,0x0440,0x0435,0x0441,0x0443,0x0440,0x0441,0x043E,0x0432)) 86 ([System.Drawing.Color]::FromArgb(44, 48, 60)) {
    Start-Process "perfmon.exe" -ArgumentList "/res"
    $f4Form.Hide()
}
New-F4Button (U @(0x041F,0x0435,0x0440,0x0435,0x0437,0x0430,0x043F,0x0443,0x0441,0x0442,0x0438,0x0442,0x044C,0x0020,0x041F,0x0440,0x043E,0x0432,0x043E,0x0434,0x043D,0x0438,0x043A)) 126 ([System.Drawing.Color]::FromArgb(44, 48, 60)) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process "explorer.exe"
    $f4Form.Hide()
}
New-F4Button (U @(0x0421,0x0431,0x0440,0x043E,0x0441,0x0438,0x0442,0x044C,0x0020,0x043A,0x044D,0x0448,0x0020,0x0441,0x0435,0x0442,0x0438,0x0020,0x0044,0x004E,0x0053)) 166 ([System.Drawing.Color]::FromArgb(44, 48, 60)) {
    Start-Process "ipconfig.exe" -ArgumentList "/flushdns" -WindowStyle Hidden
    $f4Form.Hide()
}
New-F4Button (U @(0x041E,0x0447,0x0438,0x0441,0x0442,0x0438,0x0442,0x044C,0x0020,0x043E,0x043F,0x0435,0x0440,0x0430,0x0442,0x0438,0x0432,0x043D,0x0443,0x044E,0x0020,0x043F,0x0430,0x043C,0x044F,0x0442,0x044C)) 206 ([System.Drawing.Color]::FromArgb(35, 130, 85)) {
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
$f4Form.Hide()
}
New-F4Button (U @(0x0421,0x043A,0x0440,0x044B,0x0442,0x044C,0x0020,0x043F,0x0430,0x043D,0x0435,0x043B,0x044C)) 268 ([System.Drawing.Color]::FromArgb(55, 35, 40)) {
$f4Form.Hide()
}
```powershell
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(340, 425)
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 21, 25)
$form.Opacity = [Math]::Max(0.70, [Math]::Min(1.0, $global:cfg.Opacity / 100.0))
$form.TopMost = $global:cfg.TopMost
$form.ShowInTaskbar = $false
$form.Icon = $customIcon
$form.Region = New-Object System.Drawing.Region((Get-RoundedPath 340 425 20))

$headerBg = New-Object System.Windows.Forms.Panel
$headerBg.Location = New-Object System.Drawing.Point(0, 0)
$headerBg.Size = New-Object System.Drawing.Size(340, 86)
$headerBg.BackColor = [System.Drawing.Color]::FromArgb(28, 30, 36)
$headerBg.Cursor = 'SizeAll'
$form.Controls.Add($headerBg)

$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:targetX = [int](($workArea.Width - 340) / 2)
$script:targetY = [int]($workArea.Height - 435)
$form.Location = New-Object System.Drawing.Point($script:targetX, $script:targetY)

$script:isDragging = $false
$script:dragOffset = [System.Drawing.Point]::Empty

$startDrag = {
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDragging = $true
        $script:dragOffset = $e.Location
    }
}
$moveDrag = {
    param($s, $e)
    if ($script:isDragging) {
        $script:targetX = [System.Windows.Forms.Cursor]::Position.X - $script:dragOffset.X
        $script:targetY = [System.Windows.Forms.Cursor]::Position.Y - $script:dragOffset.Y
        $form.Location = New-Object System.Drawing.Point($script:targetX, $script:targetY)
    }
}
$endDrag = {
    $script:isDragging = $false
}

$headerBg.Add_MouseDown($startDrag)
$headerBg.Add_MouseMove($moveDrag)
$headerBg.Add_MouseUp($endDrag)

$script:slideY = $script:targetY
$slideTimer = New-Object System.Windows.Forms.Timer
$slideTimer.Interval = 15
$slideTimer.Add_Tick({
    if ($script:slideY -gt $script:targetY) {
        $step = [Math]::Max(3, [int](($script:slideY - $script:targetY) / 2))
        $script:slideY -= $step
        if ($script:slideY -lt $script:targetY) { $script:slideY = $script:targetY }
        $form.Top = $script:slideY
    } else {
        $slideTimer.Stop()
    }
})

function Show-Menu {
    if ($global:cfg.Slide) {
        $script:slideY = $script:targetY + 45
        $form.Location = New-Object System.Drawing.Point($script:targetX, $script:slideY)
        $form.Show()
        $form.Activate()
        $slideTimer.Start()
    } else {
        $form.Location = New-Object System.Drawing.Point($script:targetX, $script:targetY)
        $form.Show()
        $form.Activate()
    }
}

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = $customIcon
$trayIcon.Text = (U @(0x0411,0x044B,0x0441,0x0442,0x0440,0x043E,0x0435,0x0020,0x043C,0x0435,0x043D,0x044E))
$trayIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$exitItem = $trayMenu.Items.Add((U @(0x0412,0x044B,0x0445,0x043E,0x0434)))
$trayIcon.ContextMenuStrip = $trayMenu

$trayIcon.Add_MouseClick({
    param($src, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible) { $form.Hide() } else { Show-Menu }
    }
})

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = (U @(0x0411,0x044B,0x0441,0x0442,0x0440,0x043E,0x0435,0x0020,0x043C,0x0435,0x043D,0x044E))
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.Size = New-Object System.Drawing.Size(300, 28)
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.TextAlign = 'MiddleCenter'
$lblTitle.Cursor = 'SizeAll'
$lblTitle.Add_MouseDown($startDrag)
$lblTitle.Add_MouseMove($moveDrag)
$lblTitle.Add_MouseUp($endDrag)
$headerBg.Controls.Add($lblTitle)

$btnTab1 = New-Object System.Windows.Forms.Button
$btnTab1.Text = (U @(0x0413,0x043B,0x0430,0x0432,0x043D,0x0430,0x044F))
$btnTab1.Location = New-Object System.Drawing.Point(20, 48)
$btnTab1.Size = New-Object System.Drawing.Size(71, 30)
$btnTab1.FlatStyle = 'Flat'; $btnTab1.FlatAppearance.BorderSize = 0; $btnTab1.Cursor = 'Hand'
$btnTab1.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$btnTab1.Region = New-Object System.Drawing.Region((Get-RoundedPath 71 30 8))
$headerBg.Controls.Add($btnTab1)

$btnTab2 = New-Object System.Windows.Forms.Button
$btnTab2.Text = (U @(0x0421,0x0432,0x043E,0x0438))
$btnTab2.Location = New-Object System.Drawing.Point(96, 48)
$btnTab2.Size = New-Object System.Drawing.Size(71, 30)
$btnTab2.FlatStyle = 'Flat'; $btnTab2.FlatAppearance.BorderSize = 0; $btnTab2.Cursor = 'Hand'
$btnTab2.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$btnTab2.Region = New-Object System.Drawing.Region((Get-RoundedPath 71 30 8))
$headerBg.Controls.Add($btnTab2)

$btnTab3 = New-Object System.Windows.Forms.Button
$btnTab3.Text = (U @(0x0421,0x0438,0x0441,0x0442,0x0435,0x043C,0x0430))
$btnTab3.Location = New-Object System.Drawing.Point(172, 48)
$btnTab3.Size = New-Object System.Drawing.Size(72, 30)
$btnTab3.FlatStyle = 'Flat'; $btnTab3.FlatAppearance.BorderSize = 0; $btnTab3.Cursor = 'Hand'
$btnTab3.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$btnTab3.Region = New-Object System.Drawing.Region((Get-RoundedPath 72 30 8))
$headerBg.Controls.Add($btnTab3)

$btnTab4 = New-Object System.Windows.Forms.Button
$btnTab4.Text = (U @(0x0412,0x0438,0x0434))
$btnTab4.Location = New-Object System.Drawing.Point(249, 48)
$btnTab4.Size = New-Object System.Drawing.Size(71, 30)
$btnTab4.FlatStyle = 'Flat'; $btnTab4.FlatAppearance.BorderSize = 0; $btnTab4.Cursor = 'Hand'
$btnTab4.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$btnTab4.Region = New-Object System.Drawing.Region((Get-RoundedPath 71 30 8))
$headerBg.Controls.Add($btnTab4)

$page1 = New-Object System.Windows.Forms.Panel
$page1.Location = New-Object System.Drawing.Point(0, 92)
$page1.Size = New-Object System.Drawing.Size(340, 275)
$page1.BackColor = [System.Drawing.Color]::FromArgb(20, 21, 25)
$form.Controls.Add($page1)

$page2 = New-Object System.Windows.Forms.Panel
$page2.Location = New-Object System.Drawing.Point(0, 92)
$page2.Size = New-Object System.Drawing.Size(340, 275)
$page2.BackColor = [System.Drawing.Color]::FromArgb(20, 21, 25)
$page2.AutoScroll = $true
$page2.Visible = $false
$form.Controls.Add($page2)

$page3 = New-Object System.Windows.Forms.Panel
$page3.Location = New-Object System.Drawing.Point(0, 92)
$page3.Size = New-Object System.Drawing.Size(340, 275)
$page3.BackColor = [System.Drawing.Color]::FromArgb(20, 21, 25)
$page3.Visible = $false
$form.Controls.Add($page3)

$page4 = New-Object System.Windows.Forms.Panel
$page4.Location = New-Object System.Drawing.Point(0, 92)
$page4.Size = New-Object System.Drawing.Size(340, 275)
$page4.BackColor = [System.Drawing.Color]::FromArgb(20, 21, 25)
$page4.Visible = $false
$form.Controls.Add($page4)

$script:currentTab = 1
function Set-ActiveTab([int]$tabNum) {
    $script:currentTab = $tabNum
    $activeColor = Get-AccentColor
    $idleColor = [System.Drawing.Color]::FromArgb(40, 42, 48)

    $page1.Visible = ($tabNum -eq 1)
    $page2.Visible = ($tabNum -eq 2)
    $page3.Visible = ($tabNum -eq 3)
    $page4.Visible = ($tabNum -eq 4)

    $btnTab1.BackColor = if ($tabNum -eq 1) { $activeColor } else { $idleColor }
    $btnTab2.BackColor = if ($tabNum -eq 2) { $activeColor } else { $idleColor }
    $btnTab3.BackColor = if ($tabNum -eq 3) { $activeColor } else { $idleColor }
    $btnTab4.BackColor = if ($tabNum -eq 4) { $activeColor } else { $idleColor }

    $btnTab1.ForeColor = if ($tabNum -eq 1) { 'White' } else { 'LightGray' }
    $btnTab2.ForeColor = if ($tabNum -eq 2) { 'White' } else { 'LightGray' }
    $btnTab3.ForeColor = if ($tabNum -eq 3) { 'White' } else { 'LightGray' }
    $btnTab4.ForeColor = if ($tabNum -eq 4) { 'White' } else { 'LightGray' }
}

$btnTab1.Add_Click({ Set-ActiveTab 1 })
$btnTab2.Add_Click({ Set-ActiveTab 2 })
$btnTab3.Add_Click({ Set-ActiveTab 3 })
$btnTab4.Add_Click({ Set-ActiveTab 4 })
Set-ActiveTab 1

function New-AppButton($parent, [string]$text, [int]$y, [System.Drawing.Color]$baseColor, [string]$exePath) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point(20, $y)
    $btn.Size = New-Object System.Drawing.Size(300, 40)
    $btn.BackColor = $baseColor
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = 'Hand'
    $btn.Region = New-Object System.Drawing.Region((Get-RoundedPath 300 40 10))

    $hoverColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, $baseColor.R + 22),
        [Math]::Min(255, $baseColor.G + 22),
        [Math]::Min(255, $baseColor.B + 22)
    )

    $btn.Add_MouseEnter({
        $btn.BackColor = $hoverColor
        $btn.Location = New-Object System.Drawing.Point(16, ($y - 1))
        $btn.Size = New-Object System.Drawing.Size(308, 42)
        $btn.Region = New-Object System.Drawing.Region((Get-RoundedPath 308 42 10))
    }.GetNewClosure())

    $btn.Add_MouseLeave({
        $btn.BackColor = $baseColor
        $btn.Location = New-Object System.Drawing.Point(20, $y)
        $btn.Size = New-Object System.Drawing.Size(300, 40)
        $btn.Region = New-Object System.Drawing.Region((Get-RoundedPath 300 40 10))
    }.GetNewClosure())

    $btn.Add_Click({
        if ($exePath -and (Test-Path $exePath)) {
            Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath)
        }
    }.GetNewClosure())

    $parent.Controls.Add($btn)
    return $btn
}
function New-GridButton($parent, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [System.Drawing.Color]$baseColor) {
$btn = New-Object System.Windows.Forms.Button
$btn.Text = $text
$btn.Location = New-Object System.Drawing.Point($x, $y)
$btn.Size = New-Object System.Drawing.Size($w, $h)
$btn.BackColor = $baseColor
$btn.ForeColor = [System.Drawing.Color]::White
$btn.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$btn.FlatStyle = 'Flat'
$btn.FlatAppearance.BorderSize = 0
$btn.Cursor = 'Hand'
$btn.Region = New-Object System.Drawing.Region((Get-RoundedPath $w $h 9))
$parent.Controls.Add($btn)
return $btn
}
$robloxExe = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions\version-*\RobloxPlayerBeta.exe" -ErrorAction SilentlyContinue |
Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $robloxExe) { $robloxExe = "C:\Users\User\AppData\Local\Roblox\Versions\version-2c6fd5e09aaf4cfa\RobloxPlayerBeta.exe" }
$mainApps = @(
@{ Name = "Visual Studio Code"; Color = [System.Drawing.Color]::FromArgb(0, 120, 212);  Path = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" },
@{ Name = "Telegram";           Color = [System.Drawing.Color]::FromArgb(42, 171, 238); Path = "$env:APPDATA\Telegram Desktop\Telegram.exe" },
@{ Name = "Steam";              Color = [System.Drawing.Color]::FromArgb(42, 71, 94);   Path = "C:\Program Files (x86)\Steam\steam.exe" },
@{ Name = "Minecraft";          Color = [System.Drawing.Color]::FromArgb(56, 142, 60);  Path = "C:\Users\User\AppData\Roaming.tlauncher\legacy\Minecraft\LL.exe" },
@{ Name = "Roblox";             Color = [System.Drawing.Color]::FromArgb(26, 86, 219);  Path = $robloxExe }
)
$yOffset = 6
foreach ($app in $mainApps) {
New-AppButton $page1 $app.Name $yOffset $app.Color $app.Path | Out-Null
$yOffset += 50
}
$global:customApps = @()
if (Test-Path $configFile) {
try {
$loaded = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($loaded) { $global:customApps = @($loaded) }
} catch {}
}
function Save-CustomApps {
$global:customApps | ConvertTo-Json -Depth 2 | Set-Content $configFile -Encoding UTF8
}
function Update-Page2 {
$page2.Controls.Clear()
$yPos = 6
$btnAdd = New-AppButton $page2 ("+ " + (U @(0x0414,0x043E,0x0431,0x0430,0x0432,0x0438,0x0442,0x044C,0x0020,0x043F,0x0440,0x043E,0x0433,0x0440,0x0430,0x043C,0x043C,0x0443))) $yPos ([System.Drawing.Color]::FromArgb(46, 125, 50)) ""
$btnAdd.Add_Click({
$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Filter = "Programs (.exe)|.exe|All files (.)|."
if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
$appName = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
if ($appName.Length -gt 1) {
$appName = $appName.Substring(0,1).ToUpper() + $appName.Substring(1)
}
$global:customApps += [PSCustomObject]@{ Name = $appName; Path = $dlg.FileName }
Save-CustomApps
Update-Page2
}
})
$yPos += 50
for ($i = 0; $i -lt $global:customApps.Count; $i++) {
$item = $global:customApps[$i]
$idx = $i
$cBtn = New-AppButton $page2 $item.Name $yPos ([System.Drawing.Color]::FromArgb(54, 56, 66)) $item.Path
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$delItem = $ctx.Items.Add((U @(0x0423,0x0434,0x0430,0x043B,0x0438,0x0442,0x044C)))
$delItem.Add_Click({
$global:customApps = @(for ($j = 0; $j -lt $global:customApps.Count; $j++) { if ($j -ne $idx) { $global:customApps[$j] } })
Save-CustomApps
Update-Page2
}.GetNewClosure())
$cBtn.ContextMenuStrip = $ctx
$yPos += 50
}
}
Update-Page2
$btnSleep30 = New-GridButton $page3 (U @(0x0422,0x0430,0x0439,0x043C,0x0435,0x0440,0x0020,0x041F,0x041A,0x003A,0x0020,0x0033,0x0030,0x0020,0x043C)) 20 6 146 36 ([System.Drawing.Color]::FromArgb(46, 48, 58))
$btnSleep30.Add_Click({ shutdown.exe -s -t 1800 })
$btnSleep60 = New-GridButton $page3 (U @(0x0422,0x0430,0x0439,0x043C,0x0435,0x0440,0x0020,0x041F,0x041A,0x003A,0x0020,0x0031,0x0020,0x0447)) 174 6 146 36 ([System.Drawing.Color]::FromArgb(46, 48, 58))
$btnSleep60.Add_Click({ shutdown.exe -s -t 3600 })
$btnCancelSleep = New-GridButton $page3 (U @(0x041E,0x0442,0x043C,0x0435,0x043D,0x0430,0x0020,0x0442,0x0430,0x0439,0x043C,0x0435,0x0440,0x0430)) 20 48 146 36 ([System.Drawing.Color]::FromArgb(145, 45, 55))
$btnCancelSleep.Add_Click({ shutdown.exe -a })
$btnCleanTemp = New-GridButton $page3 (U @(0x041E,0x0447,0x0438,0x0441,0x0442,0x043A,0x0430,0x0020,0x043A,0x044D,0x0448,0x0430,0x0020,0x0054,0x0065,0x006D,0x0070)) 174 48 146 36 ([System.Drawing.Color]::FromArgb(35, 130, 85))
$btnCleanTemp.Add_Click({ Remove-Item "$env:TEMP*" -Recurse -Force -ErrorAction SilentlyContinue })
$btnScreen = New-GridButton $page3 (U @(0x0421,0x043A,0x0440,0x0438,0x043D,0x0448,0x043E,0x0442,0x0020,0x044D,0x043A,0x0440,0x0430,0x043D,0x0430)) 20 90 146 36 ([System.Drawing.Color]::FromArgb(44, 48, 60))
$btnScreen.Add_Click({
$form.Hide()
Start-Sleep -Milliseconds 150
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save("$env:USERPROFILE\Desktop\Screen_" + (Get-Date -Format "HHmmss") + ".png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
$form.Show()
})
$btnLock = New-GridButton $page3 (U @(0x0411,0x043B,0x043E,0x043A,0x0438,0x0440,0x043E,0x0432,0x043A,0x0430,0x0020,0x041F,0x041A)) 174 90 146 36 ([System.Drawing.Color]::FromArgb(44, 48, 60))
$btnLock.Add_Click({ rundll32.exe user32.dll,LockWorkStation })
$btnAppData = New-GridButton $page3 (U @(0x041F,0x0430,0x043F,0x043A,0x0430,0x0020,0x0041,0x0070,0x0070,0x0044,0x0061,0x0074,0x0061)) 20 132 146 36 ([System.Drawing.Color]::FromArgb(44, 48, 60))
$btnAppData.Add_Click({ Start-Process "explorer.exe" $env:APPDATA })
$btnDevMgr = New-GridButton $page3 (U @(0x0414,0x0438,0x0441,0x043F,0x002E,0x0020,0x0443,0x0441,0x0442,0x0440,0x043E,0x0439,0x0441,0x0442,0x0432)) 174 132 146 36 ([System.Drawing.Color]::FromArgb(44, 48, 60))
$btnDevMgr.Add_Click({ Start-Process "devmgmt.msc" })
$btnMute = New-GridButton $page3 (U @(0x0412,0x043A,0x043B,0x002F,0x0412,0x044B,0x043A,0x043B,0x0020,0x0437,0x0432,0x0443,0x043A)) 20 174 146 36 ([System.Drawing.Color]::FromArgb(44, 48, 60))
$btnMute.Add_Click({
[WinCore]::keybd_event(0xAD, 0, 0, [UIntPtr]::Zero)
[WinCore]::keybd_event(0xAD, 0, 2, [UIntPtr]::Zero)
})
$btnBin = New-GridButton $page3 (U @(0x041E,0x0447,0x0438,0x0441,0x0442,0x0438,0x0442,0x044C,0x0020,0x043A,0x043E,0x0440,0x0437,0x0438,0x043D,0x0443)) 174 174 146 36 ([System.Drawing.Color]::FromArgb(44, 48, 60))
$btnBin.Add_Click({ Clear-RecycleBin -Force -ErrorAction SilentlyContinue })
$btnCombo = New-GridButton $page3 ((U @(0x0417,0x0430,0x043F,0x0443,0x0441,0x043A,0x003A,0x0020)) + "VS Code + Telegram") 20 216 300 38 ([System.Drawing.Color]::FromArgb(0, 120, 212))
$btnCombo.Add_Click({
$p1 = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
$p2 = "$env:APPDATA\Telegram Desktop\Telegram.exe"
if (Test-Path $p1) { Start-Process $p1 }
if (Test-Path $p2) { Start-Process $p2 }
})
$lblOp = New-Object System.Windows.Forms.Label
$lblOp.Text = (U @(0x041F,0x0440,0x043E,0x0437,0x0440,0x0430,0x0447,0x043D,0x043E,0x0441,0x0442,0x044C,0x0020,0x043C,0x0435,0x043D,0x044E,0x003A,0x0020)) + $global:cfg.Opacity + "%"
$lblOp.ForeColor = 'White'
$lblOp.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$lblOp.Location = New-Object System.Drawing.Point(20, 4)
$lblOp.Size = New-Object System.Drawing.Size(300, 18)
$lblOp.TextAlign = 'MiddleLeft'
$page4.Controls.Add($lblOp)
$trackOp = New-Object System.Windows.Forms.TrackBar
$trackOp.Minimum = 70
$trackOp.Maximum = 100
$trackOp.Value = [Math]::Max(70, [Math]::Min(100, $global:cfg.Opacity))
$trackOp.TickStyle = 'None'
$trackOp.AutoSize = $false
$trackOp.Location = New-Object System.Drawing.Point(20, 24)
$trackOp.Size = New-Object System.Drawing.Size(300, 24)
$trackOp.BackColor = [System.Drawing.Color]::FromArgb(20, 21, 25)
$trackOp.Add_Scroll({
$global:cfg.Opacity = $trackOp.Value
$form.Opacity = $trackOp.Value / 100.0
$lblOp.Text = (U @(0x041F,0x0440,0x043E,0x0437,0x0440,0x0430,0x0447,0x043D,0x043E,0x0441,0x0442,0x044C,0x0020,0x043C,0x0435,0x043D,0x044E,0x003A,0x0020)) + $trackOp.Value + "%"
Save-Settings
})
$page4.Controls.Add($trackOp)
$btnAccent = New-GridButton $page4 (U @(0x0426,0x0432,0x0435,0x0442,0x0020,0x0442,0x0435,0x043C,0x044B)) 20 56 146 38 (Get-AccentColor)
$btnAccent.Add_Click({
$global:cfg.Accent = ($global:cfg.Accent + 1) % $accents.Count
$btnAccent.BackColor = Get-AccentColor
Set-ActiveTab $script:currentTab
Save-Settings
})
$topOn  = U @(0x041F,0x043E,0x0432,0x0435,0x0440,0x0445,0x0020,0x043E,0x043A,0x043E,0x043D,0x003A,0x0020,0x0412,0x041A,0x041B)
$topOff = U @(0x041F,0x043E,0x0432,0x0435,0x0440,0x0445,0x0020,0x043E,0x043A,0x043E,0x043D,0x003A,0x0020,0x0412,0x042B,0x041A,0x041B)
$btnTop = New-GridButton $page4 $(if ($global:cfg.TopMost) { $topOn } else { $topOff }) 174 56 146 38 ([System.Drawing.Color]::FromArgb(46, 48, 58))
$btnTop.Add_Click({
$global:cfg.TopMost = -not $global:cfg.TopMost
$form.TopMost = $global:cfg.TopMost
$btnTop.Text = if ($global:cfg.TopMost) { $topOn } else { $topOff }
Save-Settings
})
$tbOn  = U @(0x041F,0x0430,0x043D,0x0435,0x043B,0x044C,0x003A,0x0020,0x0421,0x0442,0x0435,0x043A,0x043B,0x043E)
$tbOff = U @(0x041F,0x0430,0x043D,0x0435,0x043B,0x044C,0x003A,0x0020,0x041E,0x0431,0x044B,0x0447,0x043D,0x002E)
$btnTb = New-GridButton $page4 $(if ($global:cfg.TaskbarGlass) { $tbOn } else { $tbOff }) 20 102 146 38 ([System.Drawing.Color]::FromArgb(24, 118, 175))
$btnTb.Add_Click({
$global:cfg.TaskbarGlass = -not $global:cfg.TaskbarGlass
$btnTb.Text = if ($global:cfg.TaskbarGlass) { $tbOn } else { $tbOff }
[WinCore]::ApplyTaskbarGlass($global:cfg.TaskbarGlass)
Save-Settings
})
$wnOn  = U @(0x041E,0x043A,0x043D,0x0430,0x003A,0x0020,0x0421,0x0442,0x0435,0x043A,0x043B,0x043E)
$wnOff = U @(0x041E,0x043A,0x043D,0x0430,0x003A,0x0020,0x041E,0x0431,0x044B,0x0447,0x043D,0x002E)
$btnWn = New-GridButton $page4 $(if ($global:cfg.WinGlass) { $wnOn } else { $wnOff }) 174 102 146 38 ([System.Drawing.Color]::FromArgb(46, 48, 58))
$btnWn.Add_Click({
$global:cfg.WinGlass = -not $global:cfg.WinGlass
$btnWn.Text = if ($global:cfg.WinGlass) { $wnOn } else { $wnOff }
[WinCore]::ApplyWindowsAlpha($global:cfg.WinGlass, 228, $form.Handle, $f4Form.Handle)
Save-Settings
})
$slOn  = U @(0x0410,0x043D,0x0438,0x043C,0x0430,0x0446,0x0438,0x044F,0x003A,0x0020,0x0412,0x041A,0x041B)
$slOff = U @(0x0410,0x043D,0x0438,0x043C,0x0430,0x0446,0x0438,0x044F,0x003A,0x0020,0x0412,0x042B,0x041A,0x041B)
$btnSlide = New-GridButton $page4 $(if ($global:cfg.Slide) { $slOn } else { $slOff }) 20 148 146 38 ([System.Drawing.Color]::FromArgb(35, 130, 85))
$btnSlide.Add_Click({
$global:cfg.Slide = -not $global:cfg.Slide
$btnSlide.Text = if ($global:cfg.Slide) { $slOn } else { $slOff }
Save-Settings
})
$btnResetPos = New-GridButton $page4 (U @(0x0421,0x0431,0x0440,0x043E,0x0441,0x0020,0x043F,0x043E,0x0437,0x0438,0x0446,0x0438,0x0438)) 174 148 146 38 ([System.Drawing.Color]::FromArgb(46, 48, 58))
$btnResetPos.Add_Click({
$script:targetX = [int](($workArea.Width - 340) / 2)
$script:targetY = [int]($workArea.Height - 435)
$form.Location = New-Object System.Drawing.Point($script:targetX, $script:targetY)
})
$btnWinTheme = New-GridButton $page4 (U @(0x0422,0x0435,0x043C,0x0430,0x003A,0x0020,0x0422,0x0451,0x043C,0x043D,0x002F,0x0421,0x0432,0x0435,0x0442)) 20 194 146 38 ([System.Drawing.Color]::FromArgb(40, 44, 54))
$btnWinTheme.Add_Click({
$p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$v = if ((Get-ItemProperty $p -Name AppsUseLightTheme).AppsUseLightTheme -eq 0) { 1 } else { 0 }
Set-ItemProperty $p -Name AppsUseLightTheme -Value $v
Set-ItemProperty $p -Name SystemUsesLightTheme -Value $v
})
$btnTbAlign = New-GridButton $page4 (U @(0x041F,0x0430,0x043D,0x0435,0x043B,0x044C,0x003A,0x0020,0x0426,0x0435,0x043D,0x0442,0x0440,0x002F,0x041B,0x0435,0x0432)) 174 194 146 38 ([System.Drawing.Color]::FromArgb(40, 44, 54))
$btnTbAlign.Add_Click({
$p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$v = if ((Get-ItemProperty $p -Name TaskbarAl).TaskbarAl -eq 0) { 1 } else { 0 }
Set-ItemProperty $p -Name TaskbarAl -Value $v
})
$script:f4Down = $false
$script:sysTick = 0
$fastTimer = New-Object System.Windows.Forms.Timer
$fastTimer.Interval = 40
$fastTimer.Add_Tick({
if (([WinCore]::GetAsyncKeyState(0x73) -band 0x8000) -ne 0) {
if (-not $script:f4Down) {
$script:f4Down = $true
if ($f4Form.Visible) { $f4Form.Hide() } else { $f4Form.Show(); $f4Form.Activate() }
}
} else {
$script:f4Down = $false
}
$script:sysTick++
if ($script:sysTick -ge 40) {
$script:sysTick = 0
if ($global:cfg.TaskbarGlass) { [WinCore]::ApplyTaskbarGlass($true) }
if ($global:cfg.WinGlass)     { [WinCore]::ApplyWindowsAlpha($true, 228, $form.Handle, $f4Form.Handle) }
}
})
$fastTimer.Start()
$btnHide = New-AppButton $form (U @(0x0421,0x0432,0x0435,0x0440,0x043D,0x0443,0x0442,0x044C)) 374 ([System.Drawing.Color]::FromArgb(40, 42, 48)) ""
$btnHide.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnHide.ForeColor = 'LightGray'
$btnHide.Add_Click({ $form.Hide() })
$appContext = New-Object System.Windows.Forms.ApplicationContext
$exitItem.Add_Click({
$fastTimer.Stop()
[WinCore]::ApplyTaskbarGlass($false)
[WinCore]::ApplyWindowsAlpha($false, 255, $form.Handle, $f4Form.Handle)
$trayIcon.Visible = $false
$trayIcon.Dispose()
$appContext.ExitThread()
})
Show-Menu
if ($global:cfg.TaskbarGlass) { [WinCore]::ApplyTaskbarGlass($true) }
if ($global:cfg.WinGlass)     { [WinCore]::ApplyWindowsAlpha($true, 228, $form.Handle, $f4Form.Handle) }
[System.Windows.Forms.Application]::Run($appContext)