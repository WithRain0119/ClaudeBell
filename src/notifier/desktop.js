// 桌面通知：调用自绘弹窗脚本 popup.ps1（PowerShell + WinForms），在屏幕右下角显示提示窗口
// 不走系统通知中心（snoretoast 在本机被系统禁用，且用户要求自绘窗口）
//
// 用 `cmd /c start /b` 而非直接 spawn：直接 spawn 的子进程会在 node 退出时被终止
// （本机实测 detached:true 也无效），而 hook 场景 node 进程马上就要退出，
// 必须用 start 彻底脱离当前进程树，弹窗才能完整显示。
const { spawn } = require('child_process');
const path = require('path');
const logger = require('../logger');

const popupScript = path.join(__dirname, 'popup.ps1');

// 发送桌面弹窗：启动独立进程显示窗口，窗口成功拉起即视为发送成功
// 参数用 Base64 传递，避免命令行中文编码问题（popup.ps1 内部解码）
function sendDesktopNotification(title, message) {
  return new Promise((resolve) => {
    const args = [
      '/c', 'start', '""', '/b',
      'powershell.exe',
      '-NoProfile',
      '-WindowStyle', 'Hidden',
      '-ExecutionPolicy', 'Bypass',
      '-File', popupScript,
      '-TitleB64', Buffer.from(title, 'utf8').toString('base64'),
      '-MessageB64', Buffer.from(message, 'utf8').toString('base64'),
      '-TimeoutSec', '10',
    ];
    const child = spawn('cmd.exe', args, {
      stdio: 'ignore',
      windowsHide: true, // 隐藏 cmd 控制台窗口，只显示弹窗本身
    });
    child.on('error', (err) => {
      logger.error(`桌面弹窗启动失败：${err.message || err}`);
      resolve();
    });
    child.on('exit', (code) => {
      // start 命令本身立即返回，这里只说明拉起成功；弹窗进程的生命周期由 popup.ps1 自行管理
      if (code === 0) {
        logger.info(`桌面弹窗已启动：${title} - ${message}`);
      } else {
        logger.error(`桌面弹窗启动失败：start 退出码 ${code}`);
      }
      resolve();
    });
  });
}

module.exports = { sendDesktopNotification };
