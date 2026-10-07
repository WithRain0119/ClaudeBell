// 邮件通知：使用 nodemailer 发送邮件，默认关闭，需通过配置开启
const nodemailer = require('nodemailer');
const config = require('../config');
const logger = require('../logger');

// 发送邮件通知，失败只记日志不影响调用方
async function sendEmail(subject, text) {
  const cfg = config.getConfig();

  // 未开启则直接跳过
  if (cfg.mail.enabled !== true) {
    logger.info('邮件通知未开启，跳过');
    return;
  }

  const smtp = cfg.mail.smtp || {};
  const from = cfg.mail.from;
  const to = cfg.mail.to;

  // 必要配置缺失时直接报错返回，避免无意义的连接尝试
  if (!smtp.host || !from || !to) {
    logger.error('邮件配置不完整（需要 mail.smtp.host、mail.from、mail.to），跳过发送');
    return;
  }

  // 有用户名才启用认证（密码不写日志）
  const transport = nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.secure === true,
    auth: smtp.user ? { user: smtp.user, pass: smtp.pass } : undefined,
  });

  try {
    const info = await transport.sendMail({ from, to, subject, text });
    logger.info(`邮件已发送：${subject} -> ${to}（${info.messageId}）`);
  } catch (err) {
    logger.error(`邮件发送失败：${err.message || err}`);
  }
}

module.exports = { sendEmail };
