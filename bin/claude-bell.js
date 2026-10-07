#!/usr/bin/env node
// CLI 入口：提供 hook 事件处理、邮件开关、配置读写、测试通知等命令
const { Command } = require('commander');
const config = require('../src/config');
const logger = require('../src/logger');
const { notify } = require('../src/notifier');

// Claude Code hook 事件名 → 通知事件类型
const HOOK_EVENT_MAP = {
  Stop: 'task_complete',
  Notification: 'need_input',
};

// 从 stdin 读取全部内容（hook 事件由 Claude Code 通过 stdin 传入 JSON）
function readStdin() {
  return new Promise((resolve) => {
    // 没有管道输入时（例如手工执行命令）直接返回空，避免一直等待
    if (process.stdin.isTTY) {
      resolve('');
      return;
    }
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => resolve(data));
  });
}

// 密码类配置项脱敏
function maskValue(key, value) {
  if (key === 'mail.smtp.pass' && value) return '***';
  return typeof value === 'object' && value !== null ? JSON.stringify(value, null, 2) : value;
}

const program = new Command();

program
  .name('claude-bell')
  .description('Claude Code 桌面/邮件通知工具')
  .version(require('../package.json').version);

// ---- hook：处理 Claude Code hook 事件 ----
program
  .command('hook')
  .description('处理 Claude Code hook 事件（从 stdin 读取 JSON）')
  .action(async () => {
    const raw = (await readStdin()).trim();
    logger.info(`命令执行: hook，输入=${raw || '(空)'}`);

    if (!raw) {
      logger.warn('hook 未收到输入，忽略');
      return;
    }

    let payload;
    try {
      payload = JSON.parse(raw);
    } catch (err) {
      logger.error(`hook 输入不是合法 JSON，忽略：${err.message}`);
      return;
    }

    const eventType = HOOK_EVENT_MAP[payload.hook_event_name];
    if (!eventType) {
      logger.info(`未知 hook 事件，忽略：${payload.hook_event_name}`);
      return;
    }

    await notify(eventType, payload.message || '');
  });

// ---- mail：邮件通知开关 ----
const mail = program.command('mail').description('邮件通知开关');

mail
  .command('on')
  .description('开启邮件通知')
  .action(() => {
    logger.info('命令执行: mail on');
    config.set('mail.enabled', true);
    console.log('邮件通知已开启');
  });

mail
  .command('off')
  .description('关闭邮件通知')
  .action(() => {
    logger.info('命令执行: mail off');
    config.set('mail.enabled', false);
    console.log('邮件通知已关闭');
  });

mail
  .command('status')
  .description('查看邮件通知开关状态')
  .action(() => {
    logger.info('命令执行: mail status');
    console.log(`邮件通知：${config.get('mail.enabled') === true ? '已开启' : '已关闭'}`);
  });

// ---- config：配置读写 ----
const cfg = program.command('config').description('配置读写');

cfg
  .command('set <key> <value>')
  .description('设置配置项（value 会优先按 JSON 解析，如 true/false/数字）')
  .action((key, value) => {
    logger.info(`命令执行: config set ${key}`);
    let parsed;
    try {
      parsed = JSON.parse(value);
    } catch {
      parsed = value; // 解析失败按字符串保存
    }
    config.set(key, parsed);
    console.log(`已设置 ${key} = ${maskValue(key, parsed)}`);
  });

cfg
  .command('get <key>')
  .description('读取配置项（mail.smtp.pass 会脱敏显示）')
  .action((key) => {
    logger.info(`命令执行: config get ${key}`);
    console.log(maskValue(key, config.get(key)));
  });

// ---- test：发送测试通知 ----
program
  .command('test [eventType]')
  .description('发送测试通知，eventType 可选 task_complete / need_input')
  .action(async (eventType = 'task_complete') => {
    logger.info(`命令执行: test ${eventType}`);
    await notify(eventType, '这是一条 ClaudeBell 测试通知');
  });

// 不带参数时显示帮助
if (!process.argv.slice(2).length) {
  program.outputHelp();
}

program.parse(process.argv);
