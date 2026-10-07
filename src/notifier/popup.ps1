# ClaudeBell 自绘弹窗（PowerShell + WinForms，Windows 自带，零外部依赖）
# Apple 毛玻璃风格通知：抓取窗口背后的画面做模糊 + 乳白磨砂覆盖层，深色文字，点击任意处关闭
# 技术要点：
#   - 进程声明 Per-Monitor V2 DPI 感知（修复系统缩放导致的模糊/像素感）
#   - 手动按真实 DPI 缩放所有几何尺寸（与字体渲染比例保持一致，避免文字被裁切）
#   - 自绘毛玻璃：系统 Acrylic 材质在无边框窗口上只渲染成纯灰底（实测无效），
#     因此改为在显示前抓取窗口区域画面 → 降采样模糊 → 叠加乳白半透明覆盖层
#   - Win11 原生圆角 + CS_DROPSHADOW 系统投影
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

  # Win32 窗口辅助：任务栏探测（自动隐藏的任务栏不占工作区，会盖住卡片底部）
  # 以及关闭旧弹窗（旧卡片会被抓进新弹窗的毛玻璃背景，导致颜色发白）
  Add-Type -Namespace ClaudeBell -Name TrayWin -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindow(string cls, string win);

[DllImport("user32.dll")]
public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

[DllImport("user32.dll")]
public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

[DllImport("user32.dll")]
public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint affinity);
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

  # ---- Apple 风格配色 ----
  $fallbackBg = [System.Drawing.Color]::FromArgb(250, 250, 252) # 抓屏失败时的回退实底
  $textMain = [System.Drawing.Color]::FromArgb(29, 29, 31)     # #1D1D1F 近黑标题
  $textSub  = [System.Drawing.Color]::FromArgb(110, 110, 115)  # #6E6E73 灰色副文

  # ---- 关闭仍在屏幕上的旧弹窗 ----
  # 旧卡片会被本次抓屏捕入毛玻璃背景（再模糊+加乳白层后颜色发白发灰），
  # 且通知不应堆叠，因此每次弹出前先关掉上一张
  $closed = 0
  for ($i = 0; $i -lt 5; $i++) {
    # 注意：PowerShell 的 $null 会当成空字符串传入，必须用 [NullString]::Value 才是真正的 NULL
    $old = [ClaudeBell.TrayWin]::FindWindow([NullString]::Value, 'ClaudeBell')
    if ($old -eq [IntPtr]::Zero) { break }
    [void][ClaudeBell.TrayWin]::PostMessage($old, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) # WM_CLOSE
    $closed++
    Start-Sleep -Milliseconds 150
  }
  if ($closed -gt 0) { Write-BellLog ("已关闭 {0} 个旧弹窗（避免污染毛玻璃背景）" -f $closed) }

  # ---- 主窗体：无边框卡片 ----
  # 所有像素尺寸按 96 DPI 设计，之后统一乘以 $s（真实 DPI / 96）缩放
  $form = New-Object BellPopupForm
  $form.Text = 'ClaudeBell'
  $form.FormBorderStyle = 'None'
  $form.StartPosition = 'Manual'
  $form.TopMost = $true
  $form.ShowInTaskbar = $false

  # 创建句柄以获取真实 DPI（字体按 point 定义，渲染时自动随 DPI 放大）
  $hwnd = $form.Handle
  $g = [System.Drawing.Graphics]::FromHwnd($hwnd)
  $s = $g.DpiX / 96.0
  $g.Dispose()

  # 按 DPI 缩放几何尺寸，保证与字体比例一致（不被裁切）
  $W = [int](320 * $s); $H = [int](104 * $s)
  $form.Size = New-Object System.Drawing.Size($W, $H)
  $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
  $form.BackColor = $fallbackBg

  # 右下角定位（先定位，才能抓取该位置的背景画面）
  # 任务栏可见时把它作为下边界，避免卡片下沿被任务栏盖住
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $bottomLimit = $wa.Bottom
  $tray = [ClaudeBell.TrayWin]::FindWindow('Shell_TrayWnd', [NullString]::Value)
  if ($tray -ne [IntPtr]::Zero) {
    $trayRect = New-Object ClaudeBell.TrayWin+RECT
    if ([ClaudeBell.TrayWin]::GetWindowRect($tray, [ref]$trayRect)) {
      # 任务栏停靠在屏幕底部且明显可见时，卡片不得低于任务栏顶边
      if ($trayRect.Bottom -ge $wa.Bottom - 2 -and $trayRect.Top -lt $wa.Bottom - 4) {
        $bottomLimit = [Math]::Min($bottomLimit, $trayRect.Top)
      }
    }
  }
  $form.Left = $wa.Right - $form.Width - 16
  $form.Top = $bottomLimit - $form.Height - 16

  # Win11 原生圆角
  $corner = 2 # DWMWCP_ROUND
  [void][ClaudeBell.DwmWin]::DwmSetWindowAttribute($hwnd, 33, [ref]$corner, 4) # DWMWA_WINDOW_CORNER_PREFERENCE

  # ---- 毛玻璃背景：抓取窗口背后画面 → 模糊 → 叠加乳白磨砂层 ----
  # 每次调用都重新抓屏，因此可作为"实时"刷新使用
  function New-GlassBackground {
    $rect = New-Object System.Drawing.Rectangle($form.Left, $form.Top, $form.Width, $form.Height)

    # 1) 抓屏
    $shot = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height)
    $gs = [System.Drawing.Graphics]::FromImage($shot)
    $gs.CopyFromScreen($rect.X, $rect.Y, 0, 0, $shot.Size)
    $gs.Dispose()

    # 2) 降到 1/12 再放大 = 廉价高斯模糊（插值放大后边缘平滑）
    $sw = [Math]::Max(2, [int]($rect.Width / 12))
    $sh = [Math]::Max(2, [int]($rect.Height / 12))
    $small = New-Object System.Drawing.Bitmap($sw, $sh)
    $gsm = [System.Drawing.Graphics]::FromImage($small)
    $gsm.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
    $gsm.DrawImage($shot, 0, 0, $sw, $sh)
    $gsm.Dispose()
    $shot.Dispose()

    # 3) 模糊图放大回原尺寸 + 叠加乳白磨砂层（Apple 玻璃的乳白质感）
    # 用双线性插值放大：内容已模糊，观感与双三次无差别，但快得多（决定刷新帧率的关键一步）
    $bg = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height)
    $gb = [System.Drawing.Graphics]::FromImage($bg)
    $gb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
    $gb.DrawImage($small, 0, 0, $rect.Width, $rect.Height)
    $small.Dispose()

    $wash = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(165, 255, 255, 255))
    $gb.FillRectangle($wash, 0, 0, $rect.Width, $rect.Height)
    $wash.Dispose()
    $gb.Dispose()

    return $bg
  }

  # 取图片平均色，仅用于日志诊断（LockBits 一次读入 + 跳点采样，避免影响刷新帧率）
  function Get-AvgColorText([System.Drawing.Bitmap]$bmp) {
    $bd = $bmp.LockBits(
      (New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)),
      [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($bd.Stride * $bd.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $buf, 0, $buf.Length)
    $bmp.UnlockBits($bd)
    # Format32bppArgb 内存布局为 BGRA；每 16 个像素采一次样
    $sumR = 0; $sumG = 0; $sumB = 0; $cnt = 0
    for ($i = 0; $i -lt $buf.Length; $i += 64) {
      $sumB += $buf[$i]; $sumG += $buf[$i + 1]; $sumR += $buf[$i + 2]; $cnt++
    }
    return "RGB({0},{1},{2})" -f [int]($sumR / $cnt), [int]($sumG / $cnt), [int]($sumB / $cnt)
  }

  # 让本窗口对截图 API 隐身：定时抓屏时抓到的始终是窗口背后的画面，而不会被自己遮挡
  # （人眼照常可见；副作用是录屏/截图里不会出现这张卡片）
  $affinityOk = [ClaudeBell.TrayWin]::SetWindowDisplayAffinity($hwnd, 0x00000011) # WDA_EXCLUDEFROMCAPTURE
  Write-BellLog ("窗口对截图隐身(WDA_EXCLUDEFROMCAPTURE)={0}" -f $affinityOk)

  # 初始背景（此时窗口尚未显示，抓到的就是背后画面）
  try {
    $glass = New-GlassBackground
    $form.BackgroundImage = $glass
    Write-BellLog ("毛玻璃背景已生成 平均色={0}" -f (Get-AvgColorText $glass))
  } catch {
    Write-BellLog ("毛玻璃背景生成失败，回退实底卡片: {0}" -f $_.Exception.Message)
  }

  # 标题（近黑、加粗）
  $titleLbl = New-Object System.Windows.Forms.Label
  $titleLbl.Text = $title
  $titleLbl.ForeColor = $textMain
  $titleLbl.BackColor = [System.Drawing.Color]::Transparent
  $titleLbl.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
  $titleLbl.AutoSize = $true
  $titleLbl.Location = New-Object System.Drawing.Point([int](20 * $s), [int](16 * $s))
  $form.Controls.Add($titleLbl)

  # 副文（灰色、自动换行，高度留足 3 行）
  $msgLbl = New-Object System.Windows.Forms.Label
  $msgLbl.Text = $message
  $msgLbl.ForeColor = $textSub
  $msgLbl.BackColor = [System.Drawing.Color]::Transparent
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

  # ---- 实时毛玻璃：定时重新抓屏重建背景，让玻璃跟随背后画面变化 ----
  # 仅在"窗口对截图隐身"生效时启用；否则抓到的会是卡片自身（冻结的自身画面）
  if ($affinityOk) {
    # 用哈希表做计数器：脚本块内对普通变量赋值只作用于该次调用的局部作用域，累加会失效
    $glassCounter = @{ n = 0 }
    $glassTimer = New-Object System.Windows.Forms.Timer
    # Windows 定时器精度为 15.6ms，间隔必须对齐到滴答倍数才能生效：
    # 31ms ≈ 2 个滴答 ≈ 32 帧/秒（设 50ms 会被对齐成 4 个滴答 = 62ms，反而只有 16 帧/秒）
    $glassTimer.Interval = 31
    $glassTimer.Add_Tick({
      $glassCounter.n++
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      try {
        $newBg = New-GlassBackground
        $oldBg = $form.BackgroundImage
        $form.BackgroundImage = $newBg
        if ($oldBg) { $oldBg.Dispose() }
        $glassCounter.ms = $sw.ElapsedMilliseconds
        # 每 60 帧（约 2~3 秒）记录一次平均色与单帧耗时，便于确认刷新是否跟得上
        if ($glassCounter.n % 60 -eq 0) {
          Write-BellLog ("毛玻璃实时刷新 #{0} 平均色={1} 单帧耗时={2}ms" -f $glassCounter.n, (Get-AvgColorText $newBg), $glassCounter.ms)
        }
      } catch {
        Write-BellLog ("毛玻璃刷新失败，停止刷新: {0}" -f $_.Exception.Message)
        $glassTimer.Stop()
      }
    })
    $glassTimer.Start()
  } else {
    Write-BellLog '窗口无法对截图隐身，保持静态毛玻璃背景（避免抓到卡片自身）'
  }

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
