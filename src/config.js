// 配置管理：读写 ~/.claude-bell/config.json，首次运行时从默认配置复制
const fs = require('fs');
const os = require('os');
const path = require('path');
const logger = require('./logger');

// 用户配置目录：~/.claude-bell（用 os.homedir() 拼接，不使用 ~ 字符串）
const configDir = path.join(os.homedir(), '.claude-bell');
const configPath = path.join(configDir, 'config.json');
// 项目内置默认配置
const defaultPath = path.join(__dirname, '..', 'config', 'default.json');

// 读取 JSON 文件
function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

// 确保用户配置存在：不存在则从默认配置复制一份
function ensureConfig() {
  if (fs.existsSync(configPath)) return;
  fs.mkdirSync(configDir, { recursive: true });
  const defaults = readJson(defaultPath);
  fs.writeFileSync(configPath, JSON.stringify(defaults, null, 2) + '\n', 'utf8');
  logger.info(`配置文件不存在，已从默认配置创建：${configPath}`);
}

// 读取完整配置
function getConfig() {
  ensureConfig();
  const config = readJson(configPath);
  logger.debug(`读取配置：${configPath}`);
  return config;
}

// 按点号路径读取配置项，如 mail.enabled
function get(key) {
  const config = getConfig();
  const value = key.split('.').reduce((obj, k) => (obj == null ? undefined : obj[k]), config);
  // 密码字段脱敏，不记录明文
  logger.info(`读取配置项 ${key} = ${key === 'mail.smtp.pass' && value ? '***' : JSON.stringify(value)}`);
  return value;
}

// 按点号路径设置配置项并保存
function set(key, value) {
  const config = getConfig();
  const keys = key.split('.');
  const last = keys.pop();
  let target = config;
  for (const k of keys) {
    if (typeof target[k] !== 'object' || target[k] === null) target[k] = {};
    target = target[k];
  }
  target[last] = value;
  saveConfig(config);
  // 密码字段脱敏，不记录明文
  logger.info(`设置配置项 ${key} = ${key === 'mail.smtp.pass' && value ? '***' : JSON.stringify(value)}`);
}

// 保存配置到文件
function saveConfig(config) {
  ensureConfig();
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', 'utf8');
  logger.info(`配置已保存：${configPath}`);
}

module.exports = { getConfig, get, set, saveConfig };
