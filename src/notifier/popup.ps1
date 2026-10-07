# ClaudeBell 自绘弹窗（PowerShell + WinForms，Windows 自带，零外部依赖）
# Apple 风格极简通知：白底卡片、近黑标题、灰色副文、点击任意处关闭、超时自动消失
# 技术要点：
#   - 进程声明 Per-Monitor V2 DPI 感知（修复系统缩放导致的模糊/像素感）
#   - 手动按真实 DPI 缩放所有几何尺寸（字体按 point 定义会随 DPI 自动变大，
#     窗口/坐标若不跟着放大，文字就会被裁切——即"比例不正确"的根源）
#   - Win11 DWM 原生圆角 + CS_DROPSHADOW 系统投影
# 参数用 Base64 传递，避免命令行中文/特殊字符编码问题
param(
  [string]$TitleB64 = '',
  [string]$MessageB64 = '',
  [int]$TimeoutSec = 10
)

$ErrorActionPreference = 'Stop'

# 写入项目日志（与 Node 端同一文件，便于排查；失败绝不影响弹窗）
function Write-BellLog([string]$msg) {
  try {
    $logDir = Join-Path $PSScriptRoot '..\..\logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $file = Join-Path $logDir ('claude-bell-' + (Get-Date -Format 'yyyy-MM-dd') + '.log')
    $line = '[{0}] [INFO] [popup] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $file -Value $line -Encoding UTF8
  } catch { }
}

Write-BellLog ("弹窗进程启动: PID={0} 超时={1}s 会话={2}" -f $PID, $TimeoutSec, (Get-Process -Id $PID).SessionId)

try {
  # 必须最先调用：声明 Per-Monitor V2 DPI 感知，否则高缩放屏幕下窗口被位图拉伸，产生模糊/像素感
  try {
    Add-Type -Namespace ClaudeBell -Name DpiWin -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
'@
    [void][ClaudeBell.DpiWin]::SetProcessDpiAwarenessContext([IntPtr](-4)) # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
  } catch { Write-BellLog ("DPI 感知设置失败(忽略): {0}" -f $_.Exception.Message) }

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  # Win11 原生圆角（DWM 渲染，边缘平滑无锯齿）
  Add-Type -Namespace ClaudeBell -Name DwmWin -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
'@

  # 带系统投影的无边框窗体（CS_DROPSHADOW 让无边框窗口也有阴影）
  Add-Type -TypeDefinition @'
using System;
using System.Windows.Forms;

public class BellPopupForm : Form
{
    public BellPopupForm()
    {
        this.DoubleBuffered = true; // 双缓冲，避免重绘闪烁
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ClassStyle |= 0x00020000; // CS_DROPSHADOW
            return cp;
        }
    }
}
'@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

  # Base64(UTF-8) 解码
  function Decode-B64([string]$b64) {
    if (-not $b64) { return '' }
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
  }
  $title = Decode-B64 $TitleB64
  $message = Decode-B64 $MessageB64
  Write-BellLog ("参数解码成功: 标题=[{0}] 内容=[{1}]" -f $title, $message)

  # ---- Apple 风格配色（浅色）----
  $bg      = [System.Drawing.Color]::FromArgb(252, 252, 253)  # 近白卡片底
  $textMain = [System.Drawing.Color]::FromArgb(29, 29, 31)    # #1D1D1F 近黑标题
  $textSub  = [System.Drawing.Color]::FromArgb(110, 110, 115) # #6E6E73 灰色副文

  # ---- 主窗体：无边框浅色卡片 ----
  # 所有像素尺寸按 96 DPI 设计，之后统一乘以 $s（真实 DPI / 96）缩放
  $form = New-Object BellPopupForm
  $form.Text = 'ClaudeBell'
  $form.FormBorderStyle = 'None'
  $form.StartPosition = 'Manual'
  $form.TopMost = $true
  $form.ShowInTaskbar = $false
  $form.BackColor = $bg

  # 创建句柄以获取真实 DPI（字体按 point 定义，渲染时自动随 DPI 放大）
  $hwnd = $form.Handle
  $g = [System.Drawing.Graphics]::FromHwnd($hwnd)
  $s = $g.DpiX / 96.0
  $g.Dispose()

  # 按 DPI 缩放几何尺寸，保证与字体比例一致（不被裁切）
  $W = [int](320 * $s); $H = [int](104 * $s)
  $form.Size = New-Object System.Drawing.Size($W, $H)
  $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

  # 标题（近黑、加粗）
  $titleLbl = New-Object System.Windows.Forms.Label
  $titleLbl.Text = $title
  $titleLbl.ForeColor = $textMain
  $titleLbl.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
  $titleLbl.AutoSize = $true
  $titleLbl.Location = New-Object System.Drawing.Point([int](20 * $s), [int](16 * $s))
  $form.Controls.Add($titleLbl)

  # 副文（灰色、自动换行，高度留足 3 行）
  $msgLbl = New-Object System.Windows.Forms.Label
  $msgLbl.Text = $message
  $msgLbl.ForeColor = $textSub
  $msgLbl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
  $msgLbl.AutoSize = $false
  $msgLbl.Size = New-Object System.Drawing.Size([int](284 * $s), [int](56 * $s))
  $msgLbl.Location = New-Object System.Drawing.Point([int](20 * $s), [int](44 * $s))
  $form.Controls.Add($msgLbl)

  # 点击卡片任意位置关闭（极简交互，无需按钮）
  $closeAction = { $form.Close() }
  $form.Add_Click($closeAction)
  $titleLbl.Add_Click($closeAction)
  $msgLbl.Add_Click($closeAction)

  # 超时自动关闭
  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = $TimeoutSec * 1000
  $timer.Add_Tick({ $timer.Stop(); $form.Close() })
  $timer.Start()

  # Win11 原生圆角 + 右下角定位（此时尺寸已是最终缩放值）
  $corner = 2 # DWMWCP_ROUND
  [void][ClaudeBell.DwmWin]::DwmSetWindowAttribute($hwnd, 33, [ref]$corner, 4) # DWMWA_WINDOW_CORNER_PREFERENCE
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $wa.Right - $form.Width - 16
  $form.Top = $wa.Bottom - $form.Height - 16

  Write-BellLog ("进入 ShowDialog（窗口应可见）: 位置=[{0},{1}] 尺寸=[{2},{3}] 缩放={4}" -f $form.Left, $form.Top, $form.Width, $form.Height, $s)
  $null = $form.ShowDialog()
  Write-BellLog 'ShowDialog 结束（窗口已关闭）'
  exit 0
}
catch {
  Write-BellLog ("ERROR: {0}" -f $_.Exception.Message)
  Write-Error $_
  exit 1
}
