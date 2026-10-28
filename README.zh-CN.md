# Dosi 编程智能体插件

[English](README.md) | **简体中文**

在 Claude Code（以及其他编程智能体）里直接问数据问题，答案由受治理的指标计算得出。
[Dosi](https://dosi.datus.ai) 是一个基于 Apache Ossie（原 OSI）的本地语义层。
在智能体里，它可以：

- 连接你的数仓或本地文件
- 生成语义模型
- 用指标回答问题（你要时也给出 SQL）
- 展示指标血缘
- 在问题需要时构建 ontology

一切都在你的机器上运行，没有配置向导。装好插件直接提问，插件会在你需要时逐步介绍各项功能。

## 安装

### Claude Code

在 Claude Code 提示符中输入：

```
/plugin marketplace add Datus-ai/dosi-plugins
/plugin install dosi@dosi-plugins
```

然后运行 `/reload-plugins`，或开启新会话。插件首次启动时会在后台下载最新版
dosi（约 10 秒），无需再安装其他东西。之后在对话里说“升级 dosi”就能更新到新版本；
有新版本发布时，插件也会提一句。

在 Claude Code 2.1.275 及以上版本，一行即可完成两步：
`/plugin install dosi --marketplace Datus-ai/dosi-plugins`。在 shell 中则运行
`claude plugin install dosi --marketplace Datus-ai/dosi-plugins`。

### 其他编程智能体

对 Codex、DeepSeek Harness、Gemini CLI、Grok、Cursor 或其他任何智能体说：

> 按照 https://raw.githubusercontent.com/Datus-ai/dosi-plugins/main/agent-install.md 安装 Dosi

智能体会以它支持的方式安装 dosi 和各个 skill。

## 教程：10 分钟从零到 ontology

在一个空目录里使用示例数据集（20 万条订单，含客户和商品）：

```bash
mkdir dosi-try && cd dosi-try
curl -fsSLO https://dosi.datus.ai/orders-200k.duckdb
claude
```

然后依次输入下面的提示。每一步都完整跑通过，耗时为实测值。任何时候输入 `/dosi`
都能看到当前进度和下一步可以尝试什么。

### 1. 连接数据，约 10 秒

> 帮我连上数据

插件会找到 `orders-200k.duckdb` 并直接连接，不会提问。
预期输出：一行确认，`local` 连接（duckdb，`orders-200k.duckdb`）已连上。

如果是你自己的数据，这一步会检测 dbt 项目或 Cube 的 `.env`，并询问使用哪个连接
（见[使用你自己的数据](#使用你自己的数据)）。

### 2. 构建语义模型，约 2 分钟

> 给这些数据建一个语义模型

Claude 读取 schema，写出 `dosi/model.yaml`（Apache Ossie）并完成校验。
预期结果：3 个数据集、2 个关系、约 9 个指标。随后你会收到**最多三个**关于业务含义的问题，
例如"销售额是否包含已取消的订单？"。每个问题都附带推荐答案；选一个，或者直接说"按推荐的来"。

### 3. 用指标提问，约 15 秒

> 各地区每个月的销售额是多少？

预期输出：一句话结论、一张表，以及一行注明数据来源和行数的说明。
可以随意追问："只看 north"、"按周看"、"环比呢"，或者"给我看 SQL"。

### 4. 查看数字是怎么算出来的，约 15 秒

> 销售额是怎么算出来的？

预期输出：对话中的血缘树（表 → 数据集 → 指标）。`/dosi lineage revenue` 会在面板里打开完整的血缘图；
想要网页文件时说一声，会生成一个独立的 HTML 页面。

### 5. 查询明细记录，约 20 秒

> 列出金额最大的 10 个订单，带上客户地区和商品类目

预期输出：通过 `dosi select` 得到的行级结果，关联关系由插件自动选择。再试一个实体类问题：

> 哪些客户下单次数最多？

### 6. 在插件建议时构建 ontology，约 1.5 分钟

问过几个实体类问题后（按你提问的轮数算，不按查询次数），插件会在一次回答结束时提议构建
ontology，**只提一次**：你的问题涉及好几类业务对象，花几分钟建一个 ontology，之后就能直接按业务概念提问。现在建吗？

回答"现在建"。助手在对话里写出 `dosi/ontology.yaml` 和 `dosi/mapping.yaml`，包含
Customer、Order、Product 三个概念及其关联，完成校验，只有在确实存在歧义时才会提问。
如果回答"以后再说"，要再过 10 个问题才会再次提议。

### 7. 按业务概念提问，约 20 秒

> 每个商品类目下，哪个地区的客户买得最多？

预期结果：答案通过 `Order.placed_by.region`、`Order.purchases.category` 这样的概念路径计算得出，
这些路径在之后的问题中可以复用。

## 在 Claude Code 中：状态、面板与结果表格

在 Claude Code 中，插件还会绘制自己的界面。这些都不会改变 Claude 读到的内容；
没有它们，上面的每一步也照常可用。

- **状态栏**：项目的实时状态，例如 `dosi · duckdb:local · 3 ds · 8 metrics · ontology 3`。
  每次执行 dosi 命令、每次修改 `dosi/*.yaml` 后都会更新。
- **`/dosi`**：当前连接、模型文件及其是否通过校验、数据集 / 指标 / 维度的数量、ontology，
  以及下一步。`/dosi metrics` 列出所有指标及其说明。
- **`/dosi lineage [指标]`**：打开血缘面板。在终端里以树的形式展示一个指标由什么算出，
  或一张表被哪些指标依赖；在 Claude Code Desktop 中还会绘制完整的血缘图，并高亮所选路径。
  按 `h` 可同时生成 HTML 页面。
- **输入框上方的提示条**，只在有事可做时出现：模型校验有问题、ontology 建议待回答（带按钮直接回答），
  或目录里有数据但还没有连接。
- **结果展示**：`dosi … --format json` 的结果显示为表格，下方注明数据来源和行数，
  SQL 点一下即可展开。命令出错时显示错误、原因和下一步建议。

## 使用你自己的数据

在你的项目目录中启动 Claude Code，直接问数据问题即可。插件的行为与教程相同，只有第 1 步不同：

| 目录中有什么 | 第 1 步会做什么 |
|---|---|
| dbt 项目（`dbt_project.yml`、`~/.dbt/profiles.yml`） | 用 `dosi migrate conf` 转换 profiles，并询问使用哪个 target，默认推荐项目当前的 target |
| Cube 的 `.env` | 以同样方式转换 `CUBEJS_DB_*` 配置 |
| `.duckdb` / `.sqlite` 文件 | 直接连接，与教程相同 |
| 都没有 | 询问数据在哪里（你已经说过的不再问），然后写出连接配置 |

Claude 永远看不到你的密码。需要口令时，它在配置里写一个 `${NAME}` 占位符，请你自己填：
直接在 `dosi-connections.yaml` 里换成口令（这个文件不进 git，写明文没问题），或者把 `NAME=...`
写进 `~/.config/dosi/secrets.env`。下一次调用就会生效，不用重启。
暂不支持浏览器 SSO 登录（`authenticator: externalbrowser`），请改用密钥对认证或口令。

## 插件组成

| 组件 | 作用 |
|---|---|
| `skills/dosi-connect` | 连接数仓或本地文件。用 `dosi migrate conf` 转换 dbt / Cube 配置。密钥不会进入对话 |
| `skills/dosi-model` | 生成和编辑 `dosi/model.yaml`（Apache Ossie） |
| `skills/dosi-query` | 用指标（`query`）、明细记录（`select`）和变化归因（`attribute`）回答问题 |
| `skills/dosi-view` | 在对话中和本地 HTML 页面里展示指标血缘与 ontology 图 |
| `skills/dosi-ontology` | 构建 `dosi/ontology.yaml`，并按业务概念回答问题 |
| `skills/dosi-upgrade` | 告诉你当前运行的 dosi 版本，并在你要求时安装新版本 |
| `agents/dosi-modeler`、`agents/dosi-ontologist` | 在你要求时，在后台完成建模或构建 ontology |
| `hooks/` | 安装最新版 dosi、校验每次模型修改、阻止读取连接配置，并决定下一步建议哪个功能。`register.tsx` 是 Claude Code 界面：状态栏、`/dosi`、提示条、血缘面板和结果表格 |
| `bin/dosi` | 运行插件装好的 dosi：第一次使用时装最新版，且不低于 `DOSI_MIN_VERSION`。在对话里说“升级 dosi”（`bin/dosi-upgrade`）即可更新到更新的版本 |
| `bin/dosi-reconcile`、`bin/dosi-fill-derived` | 建模辅助工具：逐格核对指标和参考数字；按 dosi 的计算写回派生指标的展开式 |
| `.codex-plugin/`、`dsh/` | 让 Codex 和 DeepSeek Harness 使用同样的 skill 和钩子 |

### 在项目中生成的文件

```
dosi/model.yaml          # Apache Ossie 语义模型：请提交
dosi/ontology.yaml       # 仅在构建 ontology 后生成：请提交
dosi-connections.yaml    # 生成的连接配置；可能包含密钥，因此会加入 .gitignore
```

## 故障排查

| 现象 | 解决办法 |
|---|---|
| `Plugin "dosi" not found in any marketplace` | Claude Code 版本低于 2.1.275。请使用上面的两行安装方式 |
| `dosi_installing` | 首次二进制下载仍在进行。稍等几秒，Claude 会自动重试 |
| 受限网络下出现 `install_failed` | 设置 `DOSI_SOURCE=oss`（阿里云镜像）或 `DOSI_SOURCE=cloudflare`，然后开启新会话 |
| 想让功能建议从头开始 | `dosi-progress status` 可查看状态。删除 `~/.claude/plugins/data/<plugin>/progress/` 下对应项目的文件 |

卸载请运行 `/plugin uninstall dosi@dosi-plugins`，下载的二进制也会一并删除。

## 隐私

一切都在本地运行。插件只会发起两类网络请求：一次性的二进制下载，以及你对自己数仓执行的查询。
没有任何遥测。

## 许可证

Elastic License 2.0。
