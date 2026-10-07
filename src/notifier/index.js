// 通知调度器：根据事件类型与配置，统一调度桌面弹窗与邮件通知
const config = require('../config');
const logger = require('../logger');
const { sendDesktopNotification } = require('./desktop');
const { sendEmail } = require('./email');

// 事件类型 → 通知标题
const TITLES = {
  task_complete: 'Claude Code 任务完成',
  need_input: 'Claude Code 需要你确认',
};

// 发送通知：按配置分别触发桌面弹窗与邮件
// 返回 Promise，便于调用方（hook 入口）等通知发完再退出；
// 邮件失败只在 email.js 内部记日志，不会 reject
async function notify(eventType, message) {
  const title = TITLES[eventType];
  if (!title) {
    logger.warn(`未知事件类型，忽略通知：${eventType}`);
    return;
  }

  const cfg = config.getConfig();
  logger.info(`通知调度开始: [${eventType}] ${title} - ${message}`);

  if (cfg.desktop.enabled) {
    await sendDesktopNotification(title, message);
  } else {
    logger.info('桌面通知未开启，跳过');
  }

  if (cfg.mail.enabled) {
    await sendEmail(title, message);
  } else {
    logger.info('邮件通知未开启，跳过');
  }

  logger.info(`通知调度结束: [${eventType}]`);
}

module.exports = { notify };
