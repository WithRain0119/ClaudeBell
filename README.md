# ClaudeBell

Claude Code 桌面/邮件通知工具：任务完成或需要确认时，在桌面右下角弹出通知（可选邮件通知）。

## 功能特性

- **桌面通知**：屏幕右下角弹出毛玻璃风格卡片，自动跟随背后画面实时模糊；点击卡片任意位置关闭，10 秒后自动消失
- **邮件通知**：可选，默认关闭；可发到任意邮箱（包括自己发给自己，方便手机提醒）
- **按日期分割的日志**：所有事件、通知、错误都记录在 `logs/claude-bell-YYYY-MM-DD.log`
- **配置管理**：配置保存在用户目录，首次运行自动生成
- **CLI 命令**：处理 hook 事件、开关邮件、读写配置、发送测试通知

## 环境要求

- Node.js v18+
- Windows 10/11（桌面通知基于系统自带的 PowerShell + WinForms，无需额外依赖）
- macOS / Linux 暂未适配桌面通知（邮件通知可用）

## 安装

```bash
git clone <仓库地址>
cd ClaudeBell
npm install

# 让 claude-bell 命令全局可用（在 Node.js 全局目录创建命令链接）
npm link
```

验证命令是否可用：

```bash
claude-bell --help
```

## 配置说明

配置文件位置：

| 场景 | 路径 |
|---|---|
| 默认（部署后） | `~/.claude-bell/config.json` |
| 开发期（可选） | 由环境变量 `CLAUDE_BELL_CONFIG_FILE` 指定，例如项目内的 `config/dev-config.json` |

文件不存在时会自动从 `config/default.json` 生成一份默认配置：

```json
{
  "desktop": { "enabled": true },
  "mail": {
    "enabled": false,
    "smtp": { "host": "", "port": 587, "secure": false, "user": "", "pass": "" },
    "from": "",
    "to": ""
  }
}
```

> 开发期想让配置留在项目里（不写入用户目录），先设置环境变量：
> - PowerShell：`$env:CLAUDE_BELL_CONFIG_FILE = "E:\claude code\Project\ClaudeBell\config\dev-config.json"`
> - bash：`export CLAUDE_BELL_CONFIG_FILE="/e/claude code/Project/ClaudeBell/config/dev-config.json"`
>
> 该文件已在 `.gitignore` 中忽略，避免邮箱授权码被提交。

### 配置邮箱（以 QQ 邮箱为例）

先在 QQ 邮箱 设置 → 账户 → 开启 SMTP 服务，获取 **16 位授权码**（不是登录密码），然后：

```bash
claude-bell config set mail.smtp.host smtp.qq.com
claude-bell config set mail.smtp.port 465
claude-bell config set mail.smtp.secure true
claude-bell config set mail.smtp.user 你的QQ号@qq.com
claude-bell config set mail.smtp.pass 你的16位授权码
claude-bell config set mail.from 你的QQ号@qq.com
claude-bell config set mail.to 收件邮箱@example.com
```

> `mail.from` 一般必须与 SMTP 账号一致；`mail.to` 可以填成发件邮箱自己，实现"自己给自己发"（手机端也能收到提醒）。

其他邮箱的服务器参数：

| 邮箱 | host | port | secure |
|---|---|---|---|
| QQ 邮箱 | `smtp.qq.com` | `465` | `true` |
| 163 邮箱 | `smtp.163.com` | `465` | `true` |
| Gmail | `smtp.gmail.com` | `465` | `true` |
| Outlook | `smtp.office365.com` | `587` | `false` |

### 开启 / 关闭邮件通知

```bash
claude-bell mail on      # 开启
claude-bell mail off     # 关闭
claude-bell mail status  # 查看状态
```

## CLI 命令

| 命令 | 说明 |
|---|---|
| `claude-bell hook` | 处理 Claude Code hook 事件（从 stdin 读取 JSON，由 Claude Code 自动调用） |
| `claude-bell mail on` | 开启邮件通知 |
| `claude-bell mail off` | 关闭邮件通知 |
| `claude-bell mail status` | 查看邮件通知开关状态 |
| `claude-bell config set <key> <value>` | 设置配置项（value 优先按 JSON 解析，如 `true`/`587`） |
| `claude-bell config get <key>` | 读取配置项（`mail.smtp.pass` 脱敏显示为 `***`） |
| `claude-bell test [eventType]` | 发送测试通知，`eventType` 可选 `task_complete`（默认）/ `need_input` |

## 集成到 Claude Code

### 1. 配置 hooks

在 `~/.claude/settings.json` 中加入 hooks（**如果文件里已有其他配置，请把 `hooks` 部分合并进去，不要覆盖整个文件**）：

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "claude-bell hook"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "claude-bell hook"
          }
        ]
      }
    ]
  }
}
```

- `Stop`：Claude Code 完成一次回复后触发 → 通知「Claude Code 任务完成」
- `Notification`：Claude Code 需要你确认或选择时触发 → 通知「Claude Code 需要你确认」

### 2. 尚未 `npm link` 时（开发期）直接用 node 调用

如果还没执行 `npm link`，把 `command` 换成 node 绝对路径：

```json
{
  "type": "command",
  "command": "node \"E:\\claude code\\Project\\ClaudeBell\\bin\\claude-bell.js\" hook"
}
```

### 3. 验证集成是否生效

```bash
claude-bell test                      # 应弹出玻璃卡片；若邮件已开启还会收到邮件
claude-bell test need_input           # 测试"需要确认"文案
```

然后在 Claude Code 里正常对话一次，任务结束时桌面应自动弹出通知。

## 日志

按日期分割，位于项目根目录 `logs/`：

```
logs/claude-bell-2026-10-07.log
```

日志中邮箱密码一律脱敏为 `***`，可直接分享排查。
