// 日志模块：同时输出到控制台和文件，按日期分割日志文件
const fs = require('fs');
const path = require('path');

// 日志目录：项目根目录下的 logs（用 __dirname 推导，不依赖 process.cwd()）
const logDir = path.join(__dirname, '..', 'logs');

// 补零：保证两位数
function pad(n) {
  return String(n).padStart(2, '0');
}

// 格式化时间戳：YYYY-MM-DD HH:MM:SS
function formatTime(date) {
  const y = date.getFullYear();
  const m = pad(date.getMonth() + 1);
  const d = pad(date.getDate());
  const h = pad(date.getHours());
  const min = pad(date.getMinutes());
  const s = pad(date.getSeconds());
  return `${y}-${m}-${d} ${h}:${min}:${s}`;
}

// 写一条日志：控制台 + 当天日志文件
function log(level, msg) {
  // error 级别传入 Error 对象时，记录堆栈信息
  if (level === 'ERROR' && msg instanceof Error) {
    msg = msg.stack || msg.message;
  }
  const time = formatTime(new Date());
  const line = `[${time}] [${level}] ${msg}`;

  // 输出到控制台
  console.log(line);

  // 输出到文件：文件名取当天日期，跨天后自动写入新文件
  const file = path.join(logDir, `claude-bell-${time.slice(0, 10)}.log`);
  fs.mkdirSync(logDir, { recursive: true });
  fs.appendFileSync(file, line + '\n', 'utf8');
}

module.exports = {
  log,
  info: (msg) => log('INFO', msg),
  warn: (msg) => log('WARN', msg),
  error: (msg) => log('ERROR', msg),
  debug: (msg) => log('DEBUG', msg),
};
