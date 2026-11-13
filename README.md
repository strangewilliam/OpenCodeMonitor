# OpenCodeMonitor

macOS 菜单栏原生应用，实时监控 [OpenCode](https://opencode.ai) Go 订阅与 Console API 的用量：花费、请求数、Token、额度百分比、逐小时/逐日趋势，一目了然。

纯 Swift 单文件实现，零第三方依赖，无需 Xcode 工程，`swiftc` 直接编译。

## 功能

- **菜单栏常驻**：今日花费 · 请求数 · 5 小时滚动窗口用量百分比（接近限额时变 🟠/🔴）
- **三档汇总**：今日（0 点起）/ 近 7 天 / 近 30 天的请求数、花费（列表价）、输入/输出/缓存 Token
- **Go 额度**：5 小时窗口 / 每周 / 每月三根警示色额度条（与 Console 官网口径一致），含重置倒计时、allowance ↔ 列表价换算
- **小时用量**：近 24 小时逐小时 Cost / Tokens 直方图（与网页 Hourly 面板同源同形，由逐条推理日志聚合）
- **逐日趋势**：计费周期内每日柱状图 + 完整每日明细
- **模型明细**：24h / 7d / 30d 分模型调用量、花费占比条、官方月额度
- **最近请求**：最近 15 条推理记录（模型、Token、耗时、成本，失败标红）
- **请求质量**：成功率、平均首字延迟（TTFT）、思考 Token 占比等
- **订阅信息**：产品档位、支付方式、周期结束时间、自动续费状态
- **连接设置**：面板内修改 API Key / 接口地址 / 刷新间隔，测试连接，一键恢复默认
- **开机自启动**：写入 LaunchAgent，可随时开关
- 深色系配色 + 彩色数据条，纯展示行不悬停高亮

## 环境要求

- macOS 13+
- Xcode Command Line Tools（`xcode-select --install`）
- 一个 OpenCode Console 的 **API Key**（在 [Console](https://opencode.ai/console) 的 Keys 页面创建）

## 安装

```bash
git clone https://github.com/<你的用户名>/OpenCodeMonitor.git
cd OpenCodeMonitor
./build.sh          # 编译并安装到 ~/Applications
open ~/Applications/OpenCodeMonitor.app
```

启动后点菜单栏图标 → **连接设置 → 修改 API Key…**，填入你的 `oc_sk_…` 保存即可，数据几秒内出现。

配置文件位于 `~/Library/Application Support/OpenCodeMonitor/config.json`（权限 600，Key 只存在本地）：

```json
{
  "apiKey": "oc_sk_…",
  "apiBaseURL": "https://opencode.ai/console/api",
  "consoleURL": "https://opencode.ai/console/<你的组织>/activity/overview",
  "refreshIntervalSeconds": 300
}
```

## 数据口径说明

OpenCode Console 没有公开文档的 REST 接口，本项目使用了其中稳定的一部分（与官网页面同源）：

| 接口 | 内容 |
|---|---|
| `GET /console/api/usage/summary?range=24h\|7d\|30d` | 汇总（注意：`24h` 实际为「今日 0 点起」的自然日窗口） |
| `GET /console/api/usage/models?range=…` | 分模型明细 |
| `GET /console/api/go/status` | Go 订阅额度（5h/周/月 meters） |
| `GET /console/api/activity/go` | 逐日用量 |
| `GET /console/api/request-logs?category=inference` | 逐条推理日志（游标分页，保留 30 天） |
| `GET /console/api/go/subscription*`、`members`、`providers` 等 | 订阅与组织信息 |

两点值得知道的口径：

1. **allowance 折算**：Go 的额度计量单位是 allowance，`列表价 × (60 ÷ 该模型月限) = allowance`。例如 DeepSeek V4.1 Flash 月限 $100，$1 列表价计 $0.60 allowance；因此 Console 面板的 `$used/$60` 百分比与「列表价 ÷ $100」完全等价。应用内同时展示两种单位并互相换算。
2. **小时数据**：REST 接口无小时粒度，应用通过分页拉取逐条推理日志在本地聚合出近 24 小时直方图。

> ⚠️ 这些接口未经官方文档保证，OpenCode 改版时可能变动。接口地址可在「连接设置」中修改，无需重新编译。

## 开机自启动

菜单内点「开机自启动」即写入 `~/Library/LaunchAgents/com.strangewilliam.opencodemonitor.plist`。退出后通过 Spotlight 或 `open ~/Applications/OpenCodeMonitor.app` 重新打开。

## 从 Release 下载

到 [Releases](../../releases) 下载 `OpenCodeMonitor-vX.Y.Z.zip`，解压后拖入 `~/Applications`。首次打开若提示 Gatekeeper 警告（未签名），在「系统设置 → 隐私与安全性」点击「仍要打开」。

## 免责声明

本项目为个人工具，与 OpenCode / SST 官方无关。请自行保管 API Key，接口行为以官方为准。

## License

[MIT](./LICENSE)
