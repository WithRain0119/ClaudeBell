# ClaudeBell 自绘弹窗（PowerShell + WinForms，Windows 自带，零外部依赖）
# 用 WinForms 而非 WPF：本机 WPF 透明/合成层有兼容问题（窗口可见但不上屏），WinForms=GDI 直绘稳定
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
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  # Base64(UTF-8) 解码
  function Decode-B64([string]$b64) {
    if (-not $b64) { return '' }
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
  }
  $title = Decode-B64 $TitleB64
  $message = Decode-B64 $MessageB64
  Write-BellLog ("参数解码成功: 标题=[{0}] 内容=[{1}]" -f $title, $message)

  # 深色卡片窗口：无边框、置顶、右下角、手动定位
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'ClaudeBell'
  $form.FormBorderStyle = 'None'
  $form.StartPosition = 'Manual'
  $form.TopMost = $true
  $form.ShowInTaskbar = $false
  $form.BackColor = [System.Drawing.Color]::FromArgb(31, 41, 55)   # #1F2937
  $form.Size = New-Object System.Drawing.Size(380, 136)

  # 蓝色圆点
  $dot = New-Object System.Windows.Forms.Label
  $dot.Text = [char]0x25CF            # ●
  $dot.ForeColor = [System.Drawing.Color]::FromArgb(59, 130, 246) # #3B82F6
  $dot.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
  $dot.AutoSize = $true
  $dot.Location = New-Object System.Drawing.Point(16, 13)
  $form.Controls.Add($dot)

  # 标题
  $titleLbl = New-Object System.Windows.Forms.Label
  $titleLbl.Text = $title
  $titleLbl.ForeColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
  $titleLbl.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
  $titleLbl.AutoSize = $true
  $titleLbl.Location = New-Object System.Drawing.Point(40, 14)
  $form.Controls.Add($titleLbl)

  # 内容（自动换行）
  $msgLbl = New-Object System.Windows.Forms.Label
  $msgLbl.Text = $message
  $msgLbl.ForeColor = [System.Drawing.Color]::FromArgb(209, 213, 219)
  $msgLbl.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
  $msgLbl.AutoSize = $false
  $msgLbl.Size = New-Object System.Drawing.Size(340, 46)
  $msgLbl.Location = New-Object System.Drawing.Point(40, 44)
  $form.Controls.Add($msgLbl)

  # "知道了"按钮
  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = '知道了'
  $btn.ForeColor = [System.Drawing.Color]::White
  $btn.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
  $btn.FlatStyle = 'Flat'
  $btn.FlatAppearance.BorderSize = 0
  $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
  $btn.Size = New-Object System.Drawing.Size(90, 30)
  $btn.Location = New-Object System.Drawing.Point(274, 96)
  $btn.Add_Click({ $form.Close() })
  $form.Controls.Add($btn)

  # 超时自动关闭
  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = $TimeoutSec * 1000
  $timer.Add_Tick({ $timer.Stop(); $form.Close() })
  $timer.Start()

  # 显示在主屏幕工作区右下角
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $wa.Right - $form.Width - 16
  $form.Top = $wa.Bottom - $form.Height - 16

  Write-BellLog ("进入 ShowDialog（窗口应可见）: 位置=[{0},{1}]" -f $form.Left, $form.Top)
  $null = $form.ShowDialog()
  Write-BellLog 'ShowDialog 结束（窗口已关闭）'
  exit 0
}
catch {
  Write-BellLog ("ERROR: {0}" -f $_.Exception.Message)
  Write-Error $_
  exit 1
}
