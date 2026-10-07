# ClaudeBell

Claude Code 桌面/邮件通知工具：任务完成或需要确认时，在桌面右下角弹出通知（可选邮件通知）。

**不用一直盯着终端了** —— Claude Code 在后台跑长任务时，你可以去干别的事，任务一结束，桌面右下角会弹出卡片提醒；需要你做选择时也会提醒。开启邮件后还能收到邮件（自己发给自己，手机也能收到推送）。

## 功能特性

- **桌面通知**：屏幕右下角弹出毛玻璃风格卡片，自动跟随背后画面实时模糊；点击卡片任意位置关闭，10 秒后自动消失；多条通知自动替换而非堆叠
- **邮件通知**：可选，默认关闭；可发到任意邮箱（包括自己发给自己）
- **按日期分割的日志**：所有事件、通知、错误都记录在 `logs/claude-bell-YYYY-MM-DD.log`
- **配置管理**：配置保存在用户目录，首次运行自动生成
- **CLI 命令**：处理 hook 事件、开关邮件、读写配置、发送测试通知
- **无额外运行时依赖**：桌面弹窗基于系统自带的 PowerShell + WinForms 自绘，不需要安装通知组件

## 环境要求

- Node.js v18+
- Windows 10/11

> macOS / Linux 目前只支持邮件通知，桌面通知未适配。

## 目录结构

```
ClaudeBell/
├── bin/claude-bell.js      # CLI 入口
├── src/
│   ├── config.js           # 配置管理
│   ├── logger.js           # 日志模块
│   ├── notifier/
│   │   ├── index.js        # 通知调度器
│   │   ├── desktop.js      # 桌面通知（调用 popup.ps1）
│   │   ├── popup.ps1       # 自绘毛玻璃弹窗（PowerShell + WinForms）
│   │   └── email.js        # 邮件通知
│   └── utils.js            # 工具函数
├── config/default.json     # 默认配置
└── logs/                   # 日志目录（不入版本库）
```

## 安装

```bash
git clone <仓库地址>
cd ClaudeBell
npm install

# 让 claude-bell 命令全局可用
npm link
```

验证：

```bash
claude-bell --version
claude-bell --help
```

> Windows 上若 `npm link` 报 `EPERM: operation not permitted, symlink`，说明 Node 全局目录当前用户无写权限：改用管理员 PowerShell 执行，或改到你自己的目录 `npm config set prefix "C:\Users\<你>\AppData\Roaming\npm"`。

## 配置说明

配置文件位置：

| 场景 | 路径 |
|---|---|
| 默认（部署后） | `~/.claude-bell/config.json` |
| 开发期（可选） | 环境变量 `CLAUDE_BELL_CONFIG_FILE` 指定的路径，例如项目内 `config/dev-config.json` |

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

> **开发期**想让配置留在项目里（不写用户目录）：
> - PowerShell：`$env:CLAUDE_BELL_CONFIG_FILE = "E:\claude code\Project\ClaudeBell\config\dev-config.json"`
> - bash：`export CLAUDE_BELL_CONFIG_FILE="/e/claude code/Project/ClaudeBell/config/dev-config.json"`
>
> 该文件已被 `.gitignore` 忽略，避免邮箱授权码被提交。**部署后请不要设置这个变量**，否则 hook 会一直读项目内配置。

### 邮件配置示例（QQ 邮箱）

1. 登录 QQ 邮箱 → 设置 → 账户 → 开启 **SMTP 服务**，获取 **16 位授权码**（注意：不是 QQ 登录密码）；
2. 执行：

```bash
claude-bell config set mail.smtp.host smtp.qq.com
claude-bell config set mail.smtp.port 465
claude-bell config set mail.smtp.secure true
claude-bell config set mail.smtp.user 2094348228@qq.com
claude-bell config set mail.smtp.pass 你的16位授权码
claude-bell config set mail.from 2094348228@qq.com
claude-bell config set mail.to 2094348228@qq.com   # 填自己 = 自己给自己发
```

3. 开启邮件通知并测试：

```bash
claude-bell mail on
claude-bell test
```

其他邮箱的服务器参数：

| 邮箱 | host | port | secure |
|---|---|---|---|
| QQ 邮箱 | `smtp.qq.com` | `465` | `true` |
| 163 邮箱 | `smtp.163.com` | `465` | `true` |
| Gmail | `smtp.gmail.com` | `465` | `true` |
| Outlook | `smtp.office365.com` | `587` | `false` |

### 开关邮件通知

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
| `claude-bell config set <key> <value>` | 设置配置项（value 优先按 JSON 解析，如 `true`/`587`，解析失败按字符串保存） |
| `claude-bell config get <key>` | 读取配置项（`mail.smtp.pass` 脱敏显示为 `***`） |
| `claude-bell test [eventType]` | 发送测试通知，`eventType` 可选 `task_complete`（默认）/ `need_input` |

## 集成到 Claude Code

### 1. 配置 hooks

在 `~/.claude/settings.json` 中加入（**若文件中已有其他配置，请只把 `hooks` 部分合并进去，不要覆盖整个文件**）：

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "claude-bell hook" }]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "claude-bell hook" }]
      }
    ]
  }
}
```

- `Stop`：一次回复结束时触发 → 「Claude Code 任务完成」
- `Notification`：需要你确认或选择时触发 → 「Claude Code 需要你确认」

### 2. 未执行 `npm link` 时（开发期）

把 `command` 换成 node 绝对路径（用正斜杠，node 和 shell 都识别）：

```json
{
  "type": "command",
  "command": "node \"E:/claude code/Project/ClaudeBell/bin/claude-bell.js\" hook"
}
```

### 3. 验证集成

```bash
claude-bell test              # 应弹出玻璃卡片；邮件已开启时还会收到邮件
claude-bell test need_input   # 测试"需要确认"文案
```

然后**重启 Claude Code**（settings.json 在启动时读取），正常对话一次，任务结束时桌面应自动弹出通知。

## 日志

按日期分割，位于项目根目录：

```
logs/claude-bell-2026-10-07.log
```

日志中邮箱密码一律脱敏为 `***`，可直接分享排查。

> 用 `npm link` 安装时，日志写在**本项目目录**的 `logs/` 下（`npm link` 是指向本目录的链接）；
> 若将来通过 `npm install -g claude-bell` 安装，日志会写到全局 `node_modules/claude-bell/logs/`。排查时按实际安装方式找。

## 常见问题

**Q：桌面没有弹出通知？**

先用"二分法"判断是**程序的问题**还是 **Claude Code 没调用它**：手动模拟一次 hook 调用——

```powershell
echo '{"hook_event_name":"Stop"}' | claude-bell hook
```

- **弹窗出现了** → 程序正常，问题在 Claude Code 一侧，逐项检查：

  | 检查项 | 怎么查 |
  |---|---|
  | hooks 配置是否写对 | `~/.claude/settings.json` 里有 `Stop` 和 `Notification` 两项，`command` 是 `claude-bell hook` |
  | 是否重启过 Claude Code | settings.json 在**启动时**读取，改完必须重启才生效 |
  | 全局命令是否可用 | `claude-bell --version` 能输出版本号（不能则需重新 `npm link`） |

- **还是没弹** → 程序或本机环境问题，继续查：

  | 检查项 | 怎么查 |
  |---|---|
  | 桌面通知开关 | `claude-bell config get desktop.enabled` 应为 `true` |
  | 弹窗进程是否启动 | 日志搜 `桌面弹窗已启动`（有该行说明程序已发出，问题在弹窗渲染） |
  | 有没有报错 | 日志 `logs/claude-bell-<日期>.log` 搜 `ERROR` |
  | 是不是被"新通知替换"骗了 | 通知 10 秒自动消失，且**新通知会替换旧通知**，连发多条只会看到最后一条 |
  | 任务栏遮挡 | 自动隐藏的任务栏弹出时，卡片会自动上移避开，属正常行为 |

**Q：`claude-bell hook` 和 `claude-bell test` 有什么区别？**
`test` 用来**看通知效果**（弹窗 + 邮件长什么样），不用输入 JSON；`hook` 用来**验对接链路**（JSON 解析 → 事件名映射 → 默认文案 → 容错 → 超时）。
`hook` 平时不需要手动敲——它由 Claude Code 自动调用，只有调试、排错（见上一个问题）、回归测试时才手动执行。

**Q：通知会出现在截图、录屏或会议共享里吗？**
不会。为了让毛玻璃背景实时跟随窗口背后的画面，弹窗对截图 API 声明了隐藏（`WDA_EXCLUDEFROMCAPTURE`），因此它**人眼可见，但不会被截图/录屏/共享捕获**。这是实时毛玻璃的必要代价。

**Q：邮件发不出去？**

| 报错 | 原因 |
|---|---|
| `Invalid login: 535` | 用了邮箱登录密码，应改用 **SMTP 授权码** |
| `connect ETIMEDOUT` / `ECONNREFUSED` | 端口/加密方式选错（QQ/163 用 `465` + `secure=true`），或网络屏蔽了 SMTP |
| `Mail from must equal authorized user` | `mail.from` 必须与 `mail.smtp.user` 一致 |
| 日志显示发送成功但收不到 | 查垃圾邮件箱；换一个收件邮箱再试 |

**Q：PowerShell 里手工测试时中文变成 `?????`？**
PowerShell 向原生命令管道传参默认不是 UTF-8，先执行 `$OutputEncoding = [System.Text.Encoding]::UTF8`。（Claude Code 调用 hook 时不受影响。）

**Q：hook 会拖慢 Claude Code 吗？**
不会。桌面弹窗启动后立即返回；邮件是异步的，最多等 5 秒（超时后 hook 直接退出，退出码始终为 0，不会让 Claude Code 报错）。

**Q：日志里能看到我的邮箱密码吗？**
不能，一律显示为 `***`。

**Q：想换电脑或删掉配置？**
配置在 `~/.claude-bell/config.json`，删掉后下次运行会自动重新生成默认配置。

## 卸载

```bash
npm unlink -g claude-bell            # 移除全局命令
```

然后手动清理：

1. 删除 `~/.claude-bell/` 目录（含配置）；
2. 从 `~/.claude/settings.json` 中移除 `hooks` 里的 `Stop` 与 `Notification` 两项。

## License

[MIT](LICENSE)
