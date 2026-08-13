# Claude Code Stop 훅 토스트: 주 모니터 우측 하단 고정. 클릭하면 Claude 세션 터미널 창을 맨 앞으로 올리고 닫힘.
# 표시 단계는 포커스 비탈취(WS_EX_NOACTIVATE). 클릭 시에만 대상 창 탐색 후 SetForegroundWindow. 코드포인트 한글(인코딩 안전).
$ErrorActionPreference = 'SilentlyContinue'
try { $null = [Console]::In.ReadToEnd() } catch {}   # Stop 페이로드 흡수(미사용)

$DISMISS_MS = 0   # 자동 닫힘(ms). 0 이면 클릭 전까지 유지.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# title: "Claude Code"  /  body: "작업 완료"
$bCodes = 0xC791,0xC5C5,0x20,0xC644,0xB8CC
$bodyText = -join ($bCodes | ForEach-Object { [char]$_ })

Add-Type -WarningAction SilentlyContinue -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class TNative {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    public static int Count(string title) {
        int n = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (IsWindowVisible(h)) { StringBuilder sb = new StringBuilder(128); GetWindowText(h, sb, 128); if (sb.ToString() == title) n++; }
            return true;
        }, IntPtr.Zero);
        return n;
    }
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    // 대상 창을 복원(최소화 시)하고 포어그라운드 잠금을 우회해 맨 앞으로 올린다.
    public static void Raise(IntPtr h) {
        if (h == IntPtr.Zero) return;
        if (IsIconic(h)) ShowWindow(h, 9);   // SW_RESTORE
        IntPtr fg = GetForegroundWindow();
        uint t1 = GetWindowThreadProcessId(fg, IntPtr.Zero);
        uint t2 = GetWindowThreadProcessId(h, IntPtr.Zero);
        if (t1 != t2) AttachThreadInput(t1, t2, true);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        ShowWindow(h, 5);                     // SW_SHOW
        if (t1 != t2) AttachThreadInput(t1, t2, false);
    }
}
public class NoActForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000; cp.ExStyle |= 0x00000080; return cp; }
    }
}
"@

$pos = [System.Windows.Forms.Cursor]::Position
$wa = [System.Windows.Forms.Screen]::FromPoint($pos).WorkingArea

$form = New-Object NoActForm
$form.Text = 'ClaudeCodeToast'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(28,28,30)
$form.Width = 300
$form.Height = 86
$form.Cursor = [System.Windows.Forms.Cursors]::Hand

# 동시에 여러 개 떠도 겹치지 않게 위로 쌓기
$count = 0
try { $count = [TNative]::Count('ClaudeCodeToast') } catch {}
$form.Left = $wa.Right - $form.Width - 16
$top = $wa.Bottom - $form.Height - 16 - ($count * ($form.Height + 10))
if ($top -lt ($wa.Top + 8)) { $top = $wa.Top + 8 }
$form.Top = $top

$accent = New-Object System.Windows.Forms.Panel
$accent.Width = 5; $accent.Height = $form.Height; $accent.Left = 0; $accent.Top = 0
$accent.BackColor = [System.Drawing.Color]::FromArgb(216,122,87)
$form.Controls.Add($accent)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Claude Code'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true; $title.Left = 18; $title.Top = 12
$form.Controls.Add($title)

$body = New-Object System.Windows.Forms.Label
$body.Text = $bodyText
$body.ForeColor = [System.Drawing.Color]::Gainsboro
$body.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$body.AutoSize = $true; $body.Left = 18; $body.Top = 44
$form.Controls.Add($body)

# 클릭 시 올릴 대상 창(HWND)을 탐색한다.
# 순서: ① 보이는 콘솔창(클래식 conhost) → ② 부모 프로세스 체인의 창 → ③ 전용 터미널 창 → ④ 에디터/셸 창.
function Get-TargetWindow {
  $termRe = '^(WindowsTerminal|OpenConsole|conhost|wezterm|alacritty|mintty|Hyper|Tabby|Code|pwsh|powershell|cmd)$'
  $boundaryRe = '^(sihost|explorer|services|svchost|wininit|winlogon|userinit|csrss|RuntimeBroker|StartMenuExperienceHost)$'
  try { $cw = [TNative]::GetConsoleWindow(); if ($cw -ne [IntPtr]::Zero -and [TNative]::IsWindowVisible($cw)) { return $cw } } catch {}
  # 부모 체인은 터미널류 프로세스만 인정하고, 시스템 경계 프로세스에서 멈춘다(무관한 GUI 창 오탐 방지).
  $cur = $PID
  for ($i = 0; $i -lt 15 -and $cur -gt 0; $i++) {
    $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    if (-not $ci) { break }
    $name = $ci.Name -replace '\.exe$',''
    if ($name -match $boundaryRe) { break }
    if ($cur -ne $PID -and $name -match $termRe) {
      try { $pr = Get-Process -Id $cur -ErrorAction Stop; if ($pr.MainWindowHandle -ne [IntPtr]::Zero) { return $pr.MainWindowHandle } } catch {}
    }
    $cur = [int]$ci.ParentProcessId
  }
  $term = @(Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -and $_.Name -match '^(WindowsTerminal|OpenConsole|conhost|wezterm|alacritty|mintty|Hyper|Tabby)$' })
  if ($term.Count -ge 1) { return $term[0].MainWindowHandle }
  $alt = @(Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -and $_.Name -match '^(Code|pwsh|powershell|cmd)$' })
  if ($alt.Count -ge 1) { return $alt[0].MainWindowHandle }
  return [IntPtr]::Zero
}

$onClick = { try { [TNative]::Raise((Get-TargetWindow)) } catch {}; $form.Close() }
$form.Add_Click($onClick)
foreach ($c in $form.Controls) { $c.Cursor = [System.Windows.Forms.Cursors]::Hand; $c.Add_Click($onClick) }

if ($DISMISS_MS -gt 0) {
  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = $DISMISS_MS
  $timer.Add_Tick({ $timer.Stop(); $form.Close() })
  $form.Add_Shown({ $timer.Start() })
}

[System.Windows.Forms.Application]::Run($form)
