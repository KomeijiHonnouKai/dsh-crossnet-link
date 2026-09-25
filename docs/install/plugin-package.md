# 常驻 DSH 插件:契约、安装、启用、验证与回滚(第一阶段)

> **状态:骨架 + 只读预检 + 文档,尚未在真实 DSH 里加载验证。**
> 本文只描述**已经落盘并可复现**的东西;凡是需要你的机器上真跑一次才能确认的观察,都写在
> §9「未验证清单」里,不写成已验证。
> **最后更新**:2026-09-25(I-02/I-03/I-05/I-06/I-09/P-02:§5 新增权限前置(§5.0)、`--dump-config` 是写操作、
> 备份「取最新」判据改为 `CreationTime`、日志层级、`--dump-config` 误报读法;§6 回滚排序键同步;§7 新增
> 「采集器的调用上下文」;上一版 2026-09-24 为任务 t43 第一阶段)。
> **本次用过的命令**(只读,未执行任何安装):
> `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/plugin-preflight.ps1`
> ·`powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-tests.ps1`
> ·`.github/scripts/repo-hygiene.ps1 -Json`

## 0. 记号与前提

| 记号 | 含义 |
|---|---|
| `<REPO>` | 本仓库 checkout 的根目录(其下有 `dsh-crossnet-link\`) |
| `<DSH_HOME>` | DSH home:`$env:DSH_HOME`,默认 `$env:USERPROFILE\.dsh` |
| `<APP_DIR>` | DSH 安装目录里的 `resources\app`(其下有 `node_modules\@deepseek-ai\`) |
| `<profile>` | profile 名,日常那台是 `desktop` |
| 插件目录 | `<REPO>\dsh-crossnet-link\plugin`(本文交付的常驻插件包) |

本文**不写任何用户主目录绝对路径**:凡是会落到 `/Users/...` 形态的地方一律用上面的记号,
这是本仓库发布集的硬规则(`.github/scripts/repo-hygiene.ps1` 的 `abs-user-path` 一条)。

---

## 1. 常驻插件 ≠ 动态包

本仓库的面板有**两种**载体,它们互不替代:

| | 动态包(现在的 `panel/host-half.js` + `panel/client-half.js`) | 常驻插件(本任务新增的 `plugin/`) |
|---|---|---|
| 载入方式 | 会话里 `cordis_define` + `cordis_run`,**只活在这一个进程里** | 装进 profile,`<profile>\package.json` 的 `dsh.profile.bundles` 列出它,**每次启动都加载** |
| 代码形态 | `code.host` / `code.client` 是**函数体**,由 runner 用 `new Function` 包起来执行 | host 半边是**真 ESM 模块**(`import`/`export`);client 半边是**构建产物式浏览器 bundle** |
| 进程外可见? | 否,进程重启即消失 | 是,出现在 profile 的依赖与 bundles 列表里,可 `dsh plugin remove` |
| 出错的代价 | `cordis_stop` 立刻恢复 | 打包/入口写错会让**整个 GUI 卡在恢复模式**(本机 AGENTS.md 记录过这个真实事故) |
| 本文档 | 见 `docs/install/install.md` | 见下文 |

一句话:**动态包是"这次会话临时挂上",常驻插件是"这个 profile 永久带着"。**
所以第一阶段的常驻插件**默认 `disabled: true`** —— 让它先什么都不做。

---

## 2. 契约勘探:本机真实安装的两个常驻插件(原文 + 行号)

勘探方式:只读文件(`read`/`Select-String`/`Get-ChildItem`)。**没有**使用任何客户端 Inspect,
没有发起网络请求,没有长时间等待。

### 2.1 `dsh-ego-browser`(`<DSH_HOME>\profiles\desktop\node_modules\dsh-ego-browser`)

`package.json`:

- `:5` `"type": "module"` —— host 半边按 ESM 载入。
- `:6` `"main": "./lib/index.js"`。
- `:7-12` `exports`:`"."` → `./lib/index.js`、**`"./client"` → `./lib/client.js`**、`"./dsh-plugin.json"`、`"./package.json"`。
- `:13-21` `files`:`lib/`、`bin/`、`runtime/`、`cordis.patch.yml`、`dsh-plugin.json`、`THIRD_PARTY_NOTICES.md`、**`"!**/*.map"`**(发布的包不带 source map)。
- `:22-36` `dsh` 段:
  - `:26-28` `"bundle": { "patch": "./cordis.patch.yml" }`
  - `:29-35` `"client": { "platform": "web", "inject": ["@deepseek-ai/dsh-client-locale", "@deepseek-ai/dsh-client-ui-settings-plugins"] }`

`cordis.patch.yml`:

- `:9-14` 注释原文:*"the loader row specifier MUST equal the package.json `name` (`dsh-ego-browser`) —
  the client-modules scan matches the nearest manifest name against the Loader specifier … The earlier
  `@dsh-external/ego-browser` alias (junction key) made the scan classify the entry as "not a client row":
  host tools kept working but the watch panel silently disappeared."*
  —— **行 `name` 必须等于 package.json 的 `name`,否则 host 半边照旧能用、client 半边静默消失。**
- `:15-17` 就是那条 insert:

  ```yaml
  - insert:
      - id: ego-browser
        name: "dsh-ego-browser"
  ```

`lib/client.js`(浏览器半边,是**构建产物**):

- `:1` `window.__ModuleLoader__.load({ id: "dsh-ego-browser", factory: (require) => {`
- `:5` `var React = require("react");`
- 末尾:`exports.apply = apply; exports.inject = inject; exports.name = name; return module.exports; } });`

`lib/index.js`(host 半边,真 ESM):

- `:1-14` `import { … } from "node:fs"` / `"node:path"` / `"schemastery"` —— 真 ESM 模块。
- `:2621` `const inject = ["tools", "subprocess"];`
- `:3146-3157` `ctx.inject?.(['webServer'], (wctx) => { … initCastServer(wctx…) … })` —— 在**既有的** web 服务上挂自己的路由。
- `:1799-1880` `ctx.effect?.(() => { const webServer = ctx.get?.("webServer"); … return webServer.register({ kind: "prefix", path: API_PREFIX, handler: async (req, res) => {…} }); }, "ego-browser: /ego/api routes")`
- `:4333` `export { Config, apply, … }`

### 2.2 `@nanmicoder/dsh-agent-teams`(`…\node_modules\@nanmicoder\dsh-agent-teams`)

- `package.json:5` `"type": "module"`;`:6` `"main": "lib/index.js"`。
- `package.json:8-19` `exports`:`"."`、**`"./client"` → `./lib/client.js`**、`"./cordis.patch.yml"`、`"./package.json"`。
- `package.json:65-81` `dsh`:`"bundle": { "patch": "./cordis.patch.yml" }` + `"client": { "inject": [7 个客户端包], "platform": "web" }`。
- `package.json:222` `"build": "node scripts/clean-build.mjs && tsc … && tsdown"` —— **client 半边是构建出来的**。
- `cordis.patch.yml:10-15`:insert 一条,`id: agent-teams`,`name: '@nanmicoder/dsh-agent-teams'`(`@` 开头必须加引号);`:16-21` 带 `config`。
- **文件事实(本次实测的字节数)**:`lib/client.js` = **197202 字节**(构建产物,首行同样是
  `window.__ModuleLoader__.load({` + `id: "@nanmicoder/dsh-agent-teams"`),`lib/client.js.map` = **224758 字节**;
  同一目录另有**打包前的 ESM 源码** `lib/client/index.js` = 2872 字节,里面是
  `export const inject = ['uiConversation','slots','sessions','locale','modelDirectories','layout'];` 与
  `export function apply(ctx) {…}`。

**结论 2.2**:一个真实的常驻插件**同时**带两份客户端材料 —— 可读可 import 的 ESM 源码
(`lib/client/index.js`)与运行时真正加载的 bundle(`lib/client.js` + `.map`)。本仓库没有
tsdown/tsc 工具链,所以 `plugin/lib/client.js` 是**按同一格式手写的** bundle,并且用
`panel/plugin-preflight.ps1` 钉住「两份文件的共享正文逐字节相同」,防止漂移。

### 2.3 客户端半边到底怎么被浏览器加载(这一条决定了文件形态)

> **为什么 client 半边不是 ESM —— 以及为什么不要改回去。**
> 平台根本不把 client 半边当 ESM 加载:它被当作**经典脚本**注入页面(`document.createElement("script")`,
> 见下方 `:146-159`),脚本执行时必须自己调用 `window.__ModuleLoader__.load({ id, factory })` 注册;
> 装载结束后若这张 factory 表里没有该 `id`,模块系统**直接抛错**(`:248`
> `bundle … loaded without registering "<id>" via __ModuleLoader__.load`),而 factory 拿到的依赖入口是
> **同步 `require`**,它只认平台 seed 词 / 已物化模块 / 已注册的图行(`:300-310`)。
> 因此 `import React from "react"` 这类写法放进 bundle 里既不会被执行、也不会有解析器读它 ——
> 它只会让页面在加载那一刻报错。两个真实常驻插件的 `lib/client.js` 都是这个格式(§2.1、§2.2),
> 本机也没有 tsdown/tsc 构建链。
> **裁定(2026-09-24,captain 依本节的实测证据)**:契约里「client 半边是真 ESM」的措辞**作废**;
> 正确形态 = 运行时入口 bundle + 与它共享正文的 ESM 源码孪生(正文由 `panel/plugin-preflight.ps1`
> 逐字节比对,漂移即失败)。谁想把它改回「原生 ESM」,**先在这台机器上让页面成功加载一次再说**。

- `<APP_DIR>\node_modules\@deepseek-ai\dsh-client-modules\lib\client.js`
  - `:146-159` 默认的 bundle 装载 = `document.createElement("script"); el.src = url;` —— **经典脚本,不是 `type="module"`**。
  - `:205` `this.seed = new Map(Object.entries(options.staticModules));`
  - `:229-233` `register(registration)` —— bundle 必须自己调用 `window.__ModuleLoader__.load({id, factory})` 注册。
  - `:246-250` 装载完成后:`if (!this.factories.has(id)) throw new Error('client-modules: bundle ${url} loaded without registering "${id}" via __ModuleLoader__.load');`
  - `:300-310` 同步 `require` 只认:平台 seed 词 / 已物化的模块 / 已注册的图行,**其余一律抛错**。
  - `:311-320` `import(specifier)` 走同一张表。
- `<APP_DIR>\node_modules\@deepseek-ai\dsh-web-frontend\dist\assets\index-*.js`
  - 平台 seed 表(喂给 `__ModuleLoader__.create({staticModules: …})`)只有 **9 个**:
    `react`、`react/jsx-runtime`、`react-dom`、`react-dom/client`、`@deepseek-ai/cordis`、
    `@deepseek-ai/dsh-client-store`、`@deepseek-ai/dsh-client-ui-slots`、
    `@deepseek-ai/dsh-client-ui-primitives`、`@deepseek-ai/dsh-client-ui-dockkit`。
  - 客户端启动:`manifest.plugins.map(id)` → 逐个 `loader.create({ name: id })`。
- `<APP_DIR>\node_modules\@deepseek-ai\dsh-client-modules\lib\index.js`
  - `:140-154` `parseDshClient`:`dsh.client.platform` 必须是字符串;`inject`/`external`/`immediately` 可选。
  - `:156-166` `clientExportOf`:**`exports["./client"]` 必须是字符串或 `{default: 字符串}`**。
  - `:650-655` `platform !== 'web'` ⇒ 不产生 client 行;声明了 `dsh.client` 却没有 `exports["./client"]` ⇒ 直接抛错
    (`client-modules: ${pkg} declares dsh.client but exports no "./client" bundle`)。
  - `:775-781` `processOne`:`if (entry.options.name !== entryName || entry.fiber === void 0 || entry.disabled) continue;`
    —— **disabled 的行根本不进客户端模块图,它的 bundle 连发给页面都不会**。

### 2.4 要在「设置」里注册一个分区,需要什么(结论 + 行号)

**槽位契约**:`<APP_DIR>\node_modules\@deepseek-ai\dsh-cordis-client-runner\lib\client.js:3871-3919`

- key `settings.section`,`kind: list`,`scope: root`,一句话:*"One settings page per list entry."*;
- 注册项:`id`(**必填**,你的键)、`order`(可选,导航位置)、`label`(可选,`string | () => string`);
- ownerProps:`{ close: () => void }`;
- `declaredBy: "an entry in 'sidebar.settings' (client-ui-settings-general), so it exists while that entry is mounted"`
  —— **这个座位在设置面板挂载后才存在**,所以只能 `ctx.slots.inject('settings.section', cb)` 等它,不能假设已就绪;
- 官方示例(`:3918`)与 `panel/client-half.js` 一致:

  ```js
  return {
    inject: ['slots'],
    apply(ctx) {
      ctx.slots.inject('settings.section', () => ctx.slots.register(
        { name: 'settings.section', id: 'my-entry', order: 100, label: 'My entry' },
        () => React.createElement('div', null, 'hello'),
      ))
    },
  }
  ```

**已占用的座位**(别撞 id):`<APP_DIR>\node_modules\@deepseek-ai\dsh-client-ui-settings-plugins\lib\client.js:1761-1772`
注册 `settings.section` 的 `id: "plugins"`、`order: 15`;`:1773-1784` 注册 `settings.plugins.tab`(id `configurable`);
`:1785-1810` 用 `settings.plugin.item`(keyed)挂各插件的配置卡片。

> **口径提醒**:「设置 → 插件」页里那张**卡片列表**是 `settings.plugin.item` 座位,与本节这个
> `settings.section` **与它并非同一座位**(位置/渲染/可点击行为/生命周期都不同)。
> 本插件**只**用 `settings.plugin.item`（v0.3 起移除了早期注册过的 `settings.section`；侧边栏 tab 另走可选依赖 `dsh-better-sidebar`，不占 DSH 座位）:契约见 §2.6,
> 「启用后你会看到什么」见 §5.1。

**客户端半边可用的东西(实测)**:

- 服务:`slots`(槽位注册)、`locale`、`theme`、`sessions` 等全部是 cordis 服务,通过
  `exports.inject = ['slots']` 声明后 `ctx.slots` 使用;**不需要** `import` 任何包来拿到它们。
- 平台 seed(可直接 `require`):上面那 9 个,其中与本插件有关的只有 `react`。
- `fetch` 是浏览器全局(ego-browser 的客户端半边就是这么取数据的:`lib/client.js:327`、`:420` 等)。

**host 半边可用/用到的**:

- `ctx.subprocess`(`@deepseek-ai/dsh-subprocess-local` 提供):`resolveExecutable('powershell.exe')`
  与 `spawn({argv, cwd, stdio, graceMs})` → `handle.done` / `handle.collected.stdout.readFrom(0)`。
- `ctx.get('webServer')`(`@deepseek-ai/dsh-host-webserver`):`register({kind:'prefix'|'exact', path, handler})`
  —— `<APP_DIR>\node_modules\@deepseek-ai\dsh-host-webserver\lib\index.js:171-183`,**返回 disposer**;
  `:321-328` 前缀表"最长前缀优先"。这**不是新监听**:端口与绑定地址都还是那个既有 web 服务。

### 2.5 装载与"禁用"的语义(为什么默认 disabled 就等于什么都不做)

- `<APP_DIR>\node_modules\@deepseek-ai\cordis-plugin-loader\lib\index.js:359-378`
  `disabled` = `Boolean(options.disabled)`(`!!js` 表达式会被求值);`:389-392` `refresh()` 里
  `if (this.disabled) return;` —— **disable 的行不会 init,更不会 apply**。
- `<APP_DIR>\node_modules\@deepseek-ai\dsh-client-modules\lib\index.js:775-781` —— **客户端模块图也不含 disable 的行**(见 §2.3)。
- 装载 insert 的语义:`<APP_DIR>\node_modules\@deepseek-ai\dsh-app-boot\lib\index.js:59-107`
  - `:70-88`:patch 里有 `insert` 时,**没有 `id`** ⇒ 追加到顶层行列表(`:85`);**有 `id`** ⇒ 追加到那个 group 的 `config`(`:84`)。本插件的 patch 用的是前者(顶层追加)。
  - `:89-105`:非 insert 的 patch 按 `id` 找到目标行,先比对 `name`(`:98-101`,不匹配就告警跳过),再逐字段覆盖
    (`:102-105`)。**这就是「启用覆盖行」的机制。**
  - `:1151-1168` bundle 自带的 `cordis.patch.yml` 属于 overlay,**找不到文件即抛错**(不会被静默忽略)。
- 用户层在所有 bundle 层之后应用:`<DSH_HOME>\profiles\desktop\cordis.patch.yml:1-3`
  原文:*"Your patch layer for this dsh profile, applied after every bundle layer"*。
  ⇒ 同一个 `id` 的行会被用户层再次覆盖,所以**启用只改用户层这一个文件**。
- 这条"覆盖已插入行"的路子有源码级依据,不是猜的:
  - `<APP_DIR>\node_modules\@deepseek-ai\dsh-app-boot\lib\index.js:843-870` `loadProfileDirectory`:
    `dsh.profile.bundles` 逐项解析成 `layers`(`:849-860`),profile 自己的 `cordis.patch.yml` 单独读成 `patches`(`:861-862`);
  - 同文件 `:896-906` `composeEntries` 把两者**合进同一次** `applyEntryPatches([], [...layers.flat(), ...patches])` —— 用户层在数组末尾;
  - 同文件 `:51-52` 注释与 `:86` `buildMap(insert)`:*"Inserted entries are indexed as they are added, so a later patch in the same list can target a row an earlier patch inserted."*
    ⇒ 先由 bundle 层插入的 `dsh-crossnet-link` 行,会被后面的用户层 patch 按 `id` 命中并覆盖 `disabled`。
- 安装/卸载的落点:`<APP_DIR>\node_modules\@deepseek-ai\dsh\lib\plugin-Ddi42qoW.js`
  - `:46-78` `reconcilePlugins`:声明了 `dsh.bundle` 的依赖被写进 `dsh.profile.bundles`;被移除的会被摘掉。
  - `:101-128` `runPlugin`:profile 不存在就先按模板初始化(`:103-107`),然后 `pnpm <args>` 在 profile 目录里跑
    (`:109-114`),**exit 0 才 reconcile**(`:123`)。
  - `<APP_DIR>\node_modules\@deepseek-ai\dsh\lib\bin.js:105-116` 就是 `dsh plugin --profile <name> <pnpm 参数>`;
    `:41` 的帮助原文:`dsh plugin --profile tui add <package>`。

### 2.6 「设置 → 插件」页的**卡片**座位(t46 勘探,结论 + 行号)

**页面的真实结构**(先看清再谈座位):「设置 → 插件」本身是一个 `settings.section`
(`id: "plugins"`,order 15,声明在 `<APP_DIR>\node_modules\@deepseek-ai\dsh-client-ui-settings-plugins\lib\client.js:1761-1772`),
它内部有**两个 tab**(`settings.plugins.tab` 座位):

| tab | 谁注册 | id / order | 内容 |
|---|---|---|---|
| `all`(插件清单) | `dsh-client-ui-settings-plugin-inventory\lib\client.js:666-673` | `all` / 10 | 列出**每个已装插件行**(`ctx.remote.pluginInventory.list()`,`:655-659`):条目名、启用/禁用、fiber 状态、跳转链接。**清单由平台自带**:host 侧 `plugin-inventory` 行与 client 侧 `ui-settings-plugin-inventory` 行都在 `<APP_DIR>\node_modules\@deepseek-ai\dsh-web-app\cordis.patch.yml:101-102` 与 `:246-247`,所以它同时列出**未启用**的行 |
| `configurable`(可配置插件) | `dsh-client-ui-settings-plugins\lib\client.js:1773-1784` | `configurable` / 0 | 按**已服务的设置命名空间**逐个渲染 `settings.plugin.item` 卡片;本包自己的四张内置卡片(`:1785-1810`)也在这里 |

**卡片座位契约**:`<APP_DIR>\node_modules\@deepseek-ai\dsh-cordis-client-runner\lib\client.js:3790-3825`

- key `settings.plugin.item`,`kind: **keyed**`,`scope: root`,一句话:*"One plugin's card inside the plugin configuration section"*;
- 注册项只有一个:`key`(**必填**)—— *"Your cell key: the entry renders where the owner dispatches this exact key."*;
- ownerProps:`SettingsPluginItemOwnerProps { children?: never }` —— **卡片自己的标题/内部布局全由卡片自己画**,座位不投任何 label;
- `declaredBy: "an entry in 'settings.plugins.tab' (client-ui-settings-plugins), so it exists while that entry is mounted"`;
- 官方示例(`:3823`)就是 `ctx.slots.inject('settings.plugin.item', () => ctx.slots.register({ name:'settings.plugin.item', key:'<one key the owner dispatches>' }, () => React.createElement('div', null, 'hello')))`。

**关键门槛(这一条决定了"只注册卡片"是无效的)**:owner 是 `ConfigurablePluginsTab`,`lib/client.js:1100-1152` 的控制器:

- `:1144` `const served = new Set(mirrored.view?.namespaces.map((view) => view.ns) ?? []);`
- `:1145` `const namespaces = this.entries().flatMap((entry) => entry.options.key !== void 0 && served.has(entry.options.key) ? [entry.options.key] : []);`
- `:411-416` 渲染:`namespaces.map((ns) => renderSlot("settings.plugin.item", {}, { entryKey: ns }))`

⇒ **只有当卡片的 `key` 等于一个"已被 Host 注册并被 describe() 报告"的设置命名空间时,这张卡片才会被渲染。**
`served` 来自 `ctx.settingsScope.describe().view.namespaces[].ns`,即 Host 侧 `settings.describe()` 的结果。

**Host 侧因此必须做的一件事**:注册一个设置命名空间。

- `<APP_DIR>\node_modules\@deepseek-ai\dsh-settings\lib\index.js:288-304` `register(ns, schema, options)`:
  `ns` 必须匹配 `^[a-z][a-z0-9-]*$`(`:82-86`),`schema` 必须是**活的 schemastery schema**;
- 同文件 `:358-388` `describe()`:每个**已注册**命名空间返回一条 descriptor,`:370` 直接调 `schema.toJSON()`
  —— 没有字段的命名空间同样会出现在 `served` 里(不会因为 schema 为空被过滤);
- 一线实现(FQ 包名 `@deepseek-ai/schemastery`):`<APP_DIR>\node_modules\@deepseek-ai\dsh-client-locale\lib\index.js:1,23`
  (`import z from "@deepseek-ai/schemastery"` + `ctx.inject(['settings'], (sctx) => sctx.settings.register(NS, Schema))`);
- **第三方常驻插件的完整先例**:`<DSH_HOME>\profiles\desktop\node_modules\dsh-ego-browser`
  —— host 半边 `lib/index.js:1606-1652`(`const SETTINGS_NAMESPACE = "ego-browser"` + `sctx.settings.register(...)`,schema 来自 `import z from "schemastery"`),
  client 半边 `lib/client.js:1681-1694`(`ctx.slots.inject("settings.plugin.item", function* () { yield ctx.slots.register({ name:"settings.plugin.item", key: SETTINGS_NS, order: 60, locale: SETTINGS_NS, inject: ... }, EgoBrowserCard); })`)。
  **这就是本包 t46 照搬的形态。**

**两个座位的区别**(t43 的 `settings.section` vs t46 的 `settings.plugin.item`):

| | `settings.section`(t43) | `settings.plugin.item`(t46) |
|---|---|---|
| 位置 | 设置面板**左侧导航**里独立的一页 | 「设置 → 插件」页 → `configurable` tab 里的**一张卡片** |
| 渲染 | 整页内容列,owner 投 `label`(导航文字)与 `{ close }` | tab 里的卡片列表,owner **不投任何东西**(`children?: never`),卡片自画标题 |
| 可点击行为 | 导航项可点击切换分区 | 卡片本身没有跳转语义(跳转链接在 `all` tab 的清单行上) |
| 生命周期 | 座位由 `sidebar.settings` 条目(settings-general)声明 ⇒ 设置面板挂载期间存在 | 座位由 `settings.plugins.tab` 的 `configurable` 条目声明 ⇒ **只有插件页开着时存在**;且**还要**满足上面那条"命名空间已被服务" |
| 额外前置件 | 无(只靠 cordis 服务 `slots`) | **Host 必须注册一个设置命名空间**,client 卡片的 `key` 必须等于它 |

> 说明:上表是平台两个座位的机制对比(参考资料)。本插件自 v0.3 起**DSH 座位只用 `settings.plugin.item`**,
> 不再注册 `settings.section`(早期版本注册过的独立侧边栏分区已按用户要求移除,见 §9.1)；
> 另有一个**不属于 DSH 座位**的侧边栏 tab：它注册在可选依赖 `dsh-better-sidebar` 自己的注册表里（装了才有，未装无 tab、无报错、不 waiting）。

**"脚本经典加载 + 自注册"对两个座位是否一致?** —— **完全一致**。两个座位都只是**客户端半边**向槽位注册表登记的一行;
客户端半边只有一份(一个 bundle),它被页面按经典脚本加载、执行时自注册(§2.3),`ctx.slots.inject(...)` 等座位就绪后
`ctx.slots.register(...)`。差别只在**注入哪个 key** 与 **owner 是否投 label**,与加载方式无关。
(反证:同一份 `dsh-client-ui-settings-plugins/lib/client.js` 里 `:1761`/`:1773`/`:1785` 三种座位都由**同一个 bundle** 注册;
ego-browser 的同一个 `lib/client.js` 同时注册 `settings.plugin.item` 与它的其它 UI。)

**本包的落地与安全边界(v0.4:t46 的座位 + t47 的设置)**:

- client 半边(`lib/client.js` 与 `lib/client/index.js`，共享正文逐字节一致）**在 DSH 设置页只贡献一张可配置卡片**（座位 `settings.plugin.item`）；另有一个**侧边栏 tab**，它注册在可选依赖 `dsh-better-sidebar` 自己的注册表里、不占 DSH 座位（装了才有，未装无 tab、无报错、不 waiting）：
  `settings.plugin.item`,卡片 `key: SETTINGS_NS` = `'dsh-crossnet-link'` = 包名;
  卡片标题用显示名 **`dsh-crossnet-link`**,副标题写**插件目的**(口径 = 交接笔记 `plugin-purpose-handover.md`,
  用户 2026-09-25 确认:"在 A 电脑的 DSH 里,通过浏览器插件驱动一个已登录的通道页面,直接操作 B 电脑上运行的 DSH,
  两台 DSH 由此形成联动(agent 对 agent)"),展开体是**设置表单**,不是报告;
- host 半边注册同名命名空间,**schema 里是本插件自己的体检参数**(14 个字段,清单见下面那张表):
  这份 schema 就是"卡片可配置"的来源,也是每次写入的校验依据;
- **写值路径 = 平台自己的设置服务**:卡片用 `settingsScope.bind({ namespace }).set()/unset()/mutate()`
  (服务自带 revision 围栏,并在写入后回读用户层判断是否真的落地)写**用户层**,落点是
  `<DSH_HOME>\settings.yaml` 里以命名空间为名的顶层 section;host 半边从不调用 `update()`/`replace()`,
  插件没有自己的写接口(那条只读路由只跑采集器,不写任何设置);
- 采集器参数**全部白名单化**:枚举按允许集合校验、自由文本拒绝首字符 `-` 与控制字符并限长、
  数字必须落在 schema 的 min/max 内;任何一项不合法就**整项不传**,不会变成采集器没打算收到的参数;
- **schema 库用受保护的运行时解析**取得(`await import(specifier)`,依次试 `@deepseek-ai/schemastery` 与 `schemastery`,
  整段 try/catch),**绝不写静态 `import`**:本包装法是 `link:<插件目录>`,`link:` 目标不保证自带 `node_modules`
  (包自己的依赖不会被装进 profile),静态 import 一旦解析不到就会把整个 host 半边带下去;
  解析不到时只打一条 warning 并**跳过命名空间注册** ⇒ 卡片不渲染(fail closed),其余功能照常。
  这一点由 `panel/plugin-preflight.ps1` 的 `ns.static-import` / `ns.guarded-import` / `ns.schema-fields` 三条断言钉住。

**卡片里的 14 个设置项**(名字就是设置文档里的字段名;括号里是它喂给 `src/collect.ps1` 的参数):

| 分组 | 设置项 | 控件 | 默认 | 采集器参数 |
|---|---|---|---|---|
| 本机在这条链路里的位置 | `role` 本机视角 | 下拉(两者 / 客户端 / 服务端) | `both` | `-Role` |
| 对端与 tailnet | `peer` 对端地址 | 文本 | 空 = 不核对对端 | `-Peer` |
| 对端与 tailnet | `peerName` 对端 MagicDNS 名 | 文本 | 空 | `-PeerName` |
| 对端与 tailnet | `profile` 本机 DSH profile | 文本 | 空 = 多 profile 时记 unknown | `-Profile` |
| 对端与 tailnet | `tailnetDomain` Tailnet 域名 | 文本 | 空 = 用内置后缀模式 | `-TailnetDomain` |
| 体检口径 | `strictness` 判定严格度 | 下拉(普通 / 严格) | `normal` | `-Strictness` |
| 体检口径 | `noNative` 禁用原生探测 | 开关 | `false` | `-NoNative`(只在 true 时传) |
| 体检口径 | `lang` 报告语言 | 下拉(跟随系统 / 中文 / English) | `auto` | `-Lang` |
| 体检口径 | `port` 本机 DSH 端口 | 数字(1-65535) | 空 = 环境变量,再退内置默认 | `-Port` |
| 高级(默认折叠) | `tcpTimeoutMs` TCP 探测超时 | 数字(1000-60000) | `5000` | `-TcpTimeoutMs` |
| 高级(默认折叠) | `dnsTimeoutMs` DNS 查询超时 | 数字(1000-60000) | `4000` | `-DnsTimeoutMs` |
| 高级(默认折叠) | `commandTimeoutMs` 命令超时 | 数字(1000-600000) | `15000` | `-CommandTimeoutMs` |
| 高级(默认折叠) | `dshHome` DSH home 目录 | 文本 | 空 = 自动探测 | `-DshHome` |
| 高级(默认折叠) | `appDir` DSH 应用目录 | 文本 | 空 = 自动探测 | `-AppDir` |

安装后,本机会自动探测并填好 `port` / `profile` / `dshHome` / `appDir` 四项;对端两项(`peer` / `peerName`)与 `role` 仍需手填。

> 这张卡的语义就是"编辑这个插件的设置"(平台 docstring 原文:a header naming the plugin and what its
> settings govern, disclosing that plugin's controls in place, with the save that writes them)。
> **体检报告不属于这张卡**:报告属于只读展示面(平台对应的座位是 `settings.plugins.tab` 的 list 条),
> 不要塞回设置卡 —— 这正是 v0.4 返工要修掉的那个问题。

---

## 3. 本仓库交付的包(`plugin/`)

```
plugin/
  package.json          name dsh-crossnet-link / type module / main ./lib/index.js
                        exports: "." "./client" "./package.json"
                        dsh.bundle.patch ./cordis.patch.yml / dsh.client{platform:'web', inject:['@deepseek-ai/dsh-client-ui-slots']}
                        peerDependencies(可选): dsh-better-sidebar ^0.19.1(peerDependenciesMeta.optional = true)
  cordis.patch.yml      - insert: 一条,id 与 name 都等于 dsh-crossnet-link,**disabled: true**
  lib/index.js          host 半边:真 ESM,只读,复用 src/collect.ps1;额外注册一个**带 14 个字段**的设置命名空间(受保护),
                        并把存下来的设置白名单化地映射成采集器参数
  lib/client.js         client 半边(运行时 bundle,window.__ModuleLoader__.load 自注册;DSH 设置页只贡献 settings.plugin.item 一张卡片;侧边栏 tab 走可选依赖 dsh-better-sidebar)
  lib/client/index.js   client 半边(打包前的 ESM 源码,与上面共享正文逐字节一致)
```

- host 半边做的事只有三件:①在**既有** web 服务上注册 `POST /dsh-crossnet-link/api/posture`
  (同源校验 + `application/json` + body ≤16 KiB);②把**存下来的设置**映射成参数,只读地跑一次
  `src/collect.ps1 -CheckOnly -AsJson ...`,把**叶子字段**投影成 JSON 返回;
  ③注册设置命名空间 `dsh-crossnet-link`(t46/t47,见 §2.6)——schema 里写清本插件 14 个设置项的类型与默认值,
  这份声明让卡片可配置、让每次写入被校验。host 自己**不写**设置文档(写发生在用户保存卡片时,由平台设置服务完成)。
  它不写文件、不新增监听、不读凭据、不改任何系统设置、不重启 DSH。
- client 半边做的事只有一件(注册一张卡片:**设置表单**):`settings.plugin.item`
  (key `dsh-crossnet-link`,order 100 —— 即插件页「可配置插件」tab 里的折叠卡片,**不再注册** `settings.section`);
  读值/写值走平台服务 `settingsScope`,卡片自己不 fetch 任何东西(v0.4 起不再取数:报告不在卡里)。
- **只有 `require("react")` 一个外部依赖**(平台 seed),其余全部自包含;`settingsScope` 是 **cordis 服务查找**
  (`ctx.get` / `ctx.inject`),不是模块依赖,所以 `dsh.client.inject` 仍然只有 `@deepseek-ai/dsh-client-ui-slots`;
  schema 库是**运行时可选解析**,不是依赖。

---

## 4. 只读预检(先跑这个,再谈安装)

```powershell
$repo = '<REPO>'                       # 仓库 checkout 根(含 dsh-crossnet-link\)
$preflight = Join-Path $repo 'dsh-crossnet-link\panel\plugin-preflight.ps1'

# 默认:只看仓库内的东西,不碰任何 profile
powershell -NoProfile -ExecutionPolicy Bypass -File $preflight

# 附加:报告 <profile> 下那几个目标文件当前是否存在(仍然只读,Test-Path)
powershell -NoProfile -ExecutionPolicy Bypass -File $preflight -Profile desktop
```

### 4.1 退出码契约(t43 的 0/1/2,t46 补齐实现与自证)

| 退出码 | 含义 | 什么会触发 |
|---|---|---|
| **0** | 全部**阻断项**通过 | 允许已登记的 skip:本机 `node` 不在 PATH 时那 3 条 `node --check` 打印 `[SKIP]`,**不改变退出码**(skip 永远打印出来,绝不静默) |
| **1** | 只有**非阻断告警** | 目前只有一条:缺 `docs/install/plugin-package.md`(包照样能加载,交付物不完整) |
| **2** | **有阻断项**,或**根本没法判定** | 入口缺失(`main`/`exports` 指不到文件)/ insert 行 `id` 或 `name` 与包名不一致 / `disabled` 被改成非 `true` / 两个文件的共享正文漂移 / 某个座位注册消失 / 静态 schema import / BOM/非 ASCII/非 LF / JSX 或 TS 语法 / 读不到或解析不了输入 / 预检自身抛异常 / 根目录或 `-Profile` 不对 |

判据不是"退出码好看",而是**判不了就以 2 收场**(fail closed):解析不了、读不到、抛异常,一律 2。
脚本内自带 `trap`,把任何意外异常收敛成 2,绝不会返回契约之外的码。

**调用方式也算契约的一部分**(t46 实测):脚本用 `exit N` 设码,而 PowerShell **只在 `-File` 下保留它** ——

- `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本>` ⇒ **保留**(实测 `exit 2` 得到 2);
- `powershell -NoProfile -ExecutionPolicy Bypass -Command "& '<脚本>'"` 与点源 `. '<脚本>'` ⇒ 实测都被改写成 **1**。

所以本仓库一律用 `-File` 调用(§4 上面两行命令、以及 §4.2 的 `-SelfTest` 都是);
若你用别的包装器拿到非契约值,**以脚本打印的 `[FAIL]`/`[WARN]` 行与 `exit code:` 那一行为准**,别只看外面的 `$LASTEXITCODE`。

### 4.2 故障注入自证(`-SelfTest`)

```powershell
# 把每一种"已记录的故障"注入到 %TEMP% 的一次性副本里,断言它产生的退出码
powershell -NoProfile -ExecutionPolicy Bypass -File $preflight -SelfTest
```

只在 `%TEMP%\rtg-preflight-selftest-<pid>` 下写,跑完删除;退出码 **0** = 每种注入都产生了预期码,**2** = 有偏差。
本机实测(t46):

```
[ok]   baseline             expect 0  actual 0  findings: (none)
[ok]   entry-missing        expect 2  actual 2  findings: path.main, path.exports['.'], js.lib/index.js
[ok]   row-id-mismatch      expect 2  actual 2  findings: row.id
[ok]   row-enabled          expect 2  actual 2  findings: row.disabled
[ok]   client-twin-drift    expect 2  actual 2  findings: js.shared-body
[ok]   card-seat-missing    expect 2  actual 2  findings: seat.lib/client.js.card, seat.lib/client/index.js.card
[ok]   doc-missing          expect 1  actual 1  findings: doc.plugin-package
self-test: 7 cases  matched: 7  mismatched: 0
```

### 4.3 它逐条断言什么

1. `plugin/package.json` 能被 JSON 解析;`plugin/cordis.patch.yml` 具备最小结构(恰好一个 `- insert:` 块、
   恰好一行、只用 `key: value` 简单标量、无 TAB)。**说明**:Windows PowerShell 5.1 没有 YAML 引擎,
   所以这里用的是**有文档记录的最小结构读取器**,不是通用 YAML 解析器;通用解析发生在 profile 启动时由 Loader 完成。
2. `main` / `exports['.']` / `exports['./client']` / `exports['./package.json']` / `dsh.bundle.patch` 指向的文件**都存在**。
3. 三个 JS 文件的模块卫生:两个 ESM 半边 **`require(` 调用数 = 0**;bundle 必须自注册为
   `dsh-crossnet-link` 行,且 `require("…")` 的 specifier **只能在平台 seed 白名单里**(实测只有 `react`);
   无 JSX(元素一律 `React.createElement`)、无 TypeScript 专有语法;纯 ASCII、无 BOM、全 LF;
   两个文件的**共享正文逐字节相同**(sha256 比对)。
   另外:若 `node` 恰好在 PATH 上,会对三个文件各跑一次 `node --check`;不在 PATH 时打印 `[SKIP]`,
   计入 skipped 但**不影响退出码**(本机 `node` 不在 PATH,实测 3 条 SKIP)。
4. **卡片座位在、键都对**:两个 client 文件里 `settings.plugin.item` 注册**恰好一次**、且**不注册** `settings.section`;
   卡片 key 用 `SETTINGS_NS`(**等于包名**);host 半边声明同名命名空间,且 schema 里**有字段**
   (断言 `ns.schema-fields`:至少一个字段 schema,且**不是** `schemaFactory.object({})` 空对象)。
5. **host 半边不得有静态 schema import**,必须是受保护的运行时解析(`await import(specifier)` 在 try/catch 里)
   —— 这是"`link:` 装法下 import 解析不到也不会把 host 半边带下去"的静态保证。
6. insert 行自洽且安全:唯一一行,`id` 与 `name` 都等于 package.json 的 `name`,`disabled: true`。
7. 清单:若启用会改动哪些文件、改动前该备份什么、以及"启用覆盖行"的原文。

---

## 5. 三步启用(第 0 步是权限前置;逐条可粘贴)

### 5.0 第 0 步:权限前置(先要一次授权,再动手)

> **本节流程会写到会话工作区之外。** 目标全部落在 `<DSH_HOME>\profiles\<profile>\*`
> (默认 `$env:USERPROFILE\.dsh\profiles\<profile>\*`),不在你的会话工作区里。
> DSH 会话默认沙箱是 `workspace-write`:可写范围**只有工作区**,`<DSH_HOME>` 在工作区之外 ⇒
> **需要一次显式授权**(升级到能写 `<DSH_HOME>` 的沙箱模式 / 由用户点同意)才能继续。

| 步骤 | 会写到哪里 | 目的 | 被拒时的症状 |
|---|---|---|---|
| 第 1 步 备份 | `<DSH_HOME>\profiles\<profile>\cordis.patch.yml.bak-<时间戳>`(与源文件同目录) | 先落下可整文件还原的已知良好副本 | `UnauthorizedAccessException` / `Access is denied` |
| 第 2 步 装包 | `<DSH_HOME>\profiles\<profile>\package.json`、`pnpm-lock.yaml`、`node_modules\`、`cordis.yml` | `dsh plugin --profile <profile> add 'link:<插件目录>'` | 同上;`pnpm` 报 `EPERM` |
| 第 3 步 追加启用行 | `<DSH_HOME>\profiles\<profile>\cordis.patch.yml` | 追加三行覆盖行(见下) | `AppendAllText` 抛 `UnauthorizedAccessException` |
| 第 3 步 之后的核对 | 同目录的 `cordis.yml`(**`--dump-config` 是写操作**,见下) | `dsh --profile <profile> --dump-config` | `EPERM: operation not permitted, open '…\cordis.yml'` |
| §4 的只读预检 | 不写任何东西 | `plugin-preflight.ps1`(全部只读) | —— 这一条**不需要**授权,先跑它 |

**被拒时的正确做法(写死,不要绕过)**:停下来,**显式向用户 / 上层请求一次授权** —— 把「要写哪个文件、为什么必须写、不写会
失去什么」讲清楚(上表就是素材),拿到授权后**重跑同一条命令**。授权是「让这次写入被允许」,不是「换一种不需要授权的方式」。

**不要为了绕过授权做这些事**(它们都改变流程语义,会让「可回滚」失效):

- 不要改成写工作区内的临时路径、再手工搬到 `<DSH_HOME>` —— 中间副本不是备份,回滚时你手里没有已知良好文件;
- 不要用 `-Force` / `takeown` / `icacls` 改权限,也不要提权跑整条流程 —— 权限面被改宽之后,本文的判据不再成立;
- 不要因为「只差这一步」就跳过第 1 步备份 —— 那是整条流程里唯一影响「还能不能回滚」的一步;
- 不要把 §4 的只读预检当成授权的替代品:预检**不写**任何东西,所以它永远不需要授权,也永远不能证明「能写」。

> **只读环境下仍然可用**:§4 的预检、`src/collect.ps1 -CheckOnly`、`panel/prereq.ps1 -CheckOnly` 全部只读、不需要任何授权。
> 装包只是让插件**常驻**;只想先看结论的话,读完 §4 就可以停在这里。

> **先做一次第 4 节的预检,再照下面走。** 全程不需要 pnpm 手工命令,`dsh plugin` 会转发。
> 本包**没有发布到任何 registry**(`package.json` 里 `"private": true`),所以安装一律用 `link:<插件目录>`;
> 别试 `dsh plugin --profile <profile> add dsh-crossnet-link`(装不到)。
> `link:` 的含义是**符号链接**:profile 直接加载这份 checkout 里的代码,因此插件启用期间不要移动或删掉仓库目录。

> ⚠️ **只能从完整 checkout 用 `link:` 装,不要从「只含 `lib/` 的打包产物」装 —— 否则面板会报 `collector-missing`。**
> 采集器由 host 半边按 `../../src/collect.ps1` 相对定位(`plugin/lib/index.js` 的 `COLLECTOR_REL`),落在 `plugin/`
> 上一级目录的 `src/collect.ps1`;而 `plugin/package.json` 的 `files` 只发布 `lib/` 与 `cordis.patch.yml`,
> **不含 `src/collect.ps1`**。从完整 checkout `dsh plugin add 'link:<repo>\plugin'` 装 → `../src/collect.ps1` 找得到;
> 从打包产物(如 `npm pack` / `pnpm pack` 出的 tgz,只有 `lib/`)装 → 找不到,报 `collector-missing`。

> **下一步做什么,写在最前面**:跑完第 0 步与下面三步后,**从 DSH 自带菜单重启 DSH**(设置 → 桌面 → 重启;或退出应用再打开),
> 然后去 **设置 → 插件**,清单里 `dsh-crossnet-link` 应显示**已启用**;「可配置插件」tab 里应出现
> 一张折叠卡片 **`dsh-crossnet-link`**(副标题是插件目的,点开是**设置表单**:本机视角 / 对端地址 / 体检口径 / 高级,
> 底部「保存 / 放弃」),左侧导航**不新增任何条目**。逐条带人话、给 AI 读的版本见
> [`agent-brief.md`](agent-brief.md)。

#### 取源:同名目录已存在怎么办(先改名保留,**不要**直接覆盖)

第 1 步之前先确认 `<REPO>\dsh-crossnet-link` 是**你要用的这一份**:

| 情形 | 正确做法 |
|---|---|
| 该目录不存在 | 正常取源(clone 或拷贝)。**克隆目录名必须就叫 `dsh-crossnet-link`** —— 改名会让采集器找不到 `src/collect.ps1`(改报 `collector-missing`) |
| 目录已存在,且就是本次要用的那份(工作区干净、来源可追溯) | 直接用它,不要重复取源 |
| **目录已存在,但来源不明 / 是旧副本 / 有本地改动** | **先把旧目录改名保留**(例如 `dsh-crossnet-link.old-<时间戳>`),再取新的。**不要**直接删、**不要**直接覆盖 |

**为什么不许直接覆盖**:①旧目录里可能有对端/别人的本地改动,覆盖即丢失;②对端实测遇到过"预存同名目录 `D:\DSH\dsh-crossnet-link`
与 `_incoming\`"的场景 —— 覆盖之后你**分不清**当前跑的是哪一份;③若该目录正被 `link:` 引用,删掉它会让 profile 的链接**悬空**
(见下一条);④改名保留是**可逆**的,覆盖不是。

- **`link:` 一旦建成,目标路径永久固定**:`dsh plugin add 'link:<路径>'` 会在 profile 里建立指向**那一刻那个路径**的链接,
  **之后移动或改名插件目录都会让它找不到代码**。所以取源与改名要**在 `add` 之前**做完;已经 `add` 过还想换目录,先 `remove` 再 `add`。
- 与 I-09 同族的判据:**"目录在"不等于"这目录是对的"** —— 先看 `git rev-parse HEAD` / `git status`(如果这份 checkout 有版本库),
  确认它就是你要装的那一版,再往下走。

```powershell
$repo    = '<REPO>'
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$profile = 'desktop'                                  # 第一次务必换成一次性 profile,见 §8
$patch   = Join-Path $dshHome "profiles\$profile\cordis.patch.yml"
$plugin  = Join-Path $repo 'dsh-crossnet-link\plugin'

# ---------- 第 1 步:整文件备份 profile patch(这一步不能省) ----------
$bak = $patch + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item -LiteralPath $patch -Destination $bak -Force -ErrorAction Stop   # 关键:-ErrorAction Stop(Copy-Item 被拒是**非终止错误**)
$item = Get-Item -LiteralPath $bak -ErrorAction Stop                       # 判据①:文件真的在
"backup = $($item.FullName)"                                               # 判据②:把路径记下来,回滚只认它
"bytes  = $($item.Length)"                                                 # 判据③:Length 非 0,且与 patch 一致
"sha256 = " + (Get-FileHash -LiteralPath $bak -Algorithm SHA256).Hash      # 判据④:与源文件逐字节一致
# 期望:上面三行(backup / bytes / sha256)都真的打印出来 —— ①文件存在(不是"命令无输出")②Length 非 0 且与 $patch 相同 ③sha256 与下面这行相同
"sha256 = " + (Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash
# ⚠️ 上面两行的 sha256 必须相同;若有**任何一行没打印 / $item 为 $null / Length=0 / 哈希不同** ⇒ 备份没成功,**停下,不要继续装**
#   (`Copy-Item` 被拒抛的是**非终止错误**,后面的行照常打印,脚本会显示"备份成功"而文件根本不存在 —— 对端实测踩过)
#   判据是「文件在 + Length 非 0 + SHA256 一致」,不是「命令无输出」。
# ⚠️ 排序键必须是 CreationTime(或按文件名里的时间戳),**不能**用 LastWriteTime —— 见下面的判据说明
Get-Item -Path ($patch + '.bak-*') | Sort-Object CreationTime | Select-Object -Last 1 FullName,Length,LastWriteTime,CreationTime
Test-Path -Path ($patch + '.bak-*')                                        # 期望 True(取"最新备份"这两处都用 -Path:通配符要展开;
#   用 -LiteralPath 时 `*` 会被当字面字符,实测**一个都不返回**(False/空),别把"没列出"读成"没有备份")

# ---------- 第 2 步:装进 profile(会改 profile 的 package.json / pnpm-lock.yaml / node_modules) ----------
dsh plugin --profile $profile add ('link:' + $plugin)
# 装完自检:bundles 列表里应出现 dsh-crossnet-link
(Get-Content -LiteralPath (Join-Path $dshHome "profiles\$profile\package.json") -Raw | ConvertFrom-Json).dsh.profile.bundles
# 期望:输出里有一项 dsh-crossnet-link

# ---------- 第 3 步:把"启用覆盖行"追加到 profile patch 末尾,然后从 DSH 自带菜单重启 ----------
# 启用就是这三行(id 与 name 等于包名;无 BOM 追加,不动文件里已有的任何内容):
[IO.File]::AppendAllText($patch, "`n- id: dsh-crossnet-link`n  name: dsh-crossnet-link`n  disabled: false`n", (New-Object Text.UTF8Encoding($false)))
# 期望:不是"无输出就算成功",而是**文件真的被改了**:读回文件核对追加的三行
$tail = Get-Content -LiteralPath $patch -Encoding UTF8 -Tail 3
$tail; if ($tail -notcontains '  disabled: false') { throw "追加失败或没写进文件:$patch —— 停下,不要靠 --dump-config 猜" }
# 验证一下(dsh --dump-config 本身是写操作:只读沙箱下会报 EPERM,那是权限不是配置坏,见下一节)
dsh --profile $profile --dump-config | Select-String -SimpleMatch 'dsh-crossnet-link' -Context 0,4
# 期望:能看到 id/name 是 dsh-crossnet-link、disabled: false 的那一行
```

重启后核对两格,判据见 §5.1。这一步把「人肉编辑 YAML」换成了**一条可粘贴的追加命令**:
启用行依旧落在 profile 的用户层(覆盖包自带的 `disabled: true`,升级不丢、回滚只动一个文件),
只是由流程自动加,不用人手工改。

#### ⚠️ `dsh --dump-config` **是写操作**(错误文本会误导排障)

上面第 3 步用 `--dump-config` 做核对,但这个名字看着像"只读打印",**它不是**:

- `dsh --profile <profile> --dump-config` 内部走 `runDumpConfig` → `prepareProfile(...)` →
  **`writeFileSync(join(profile.dir, 'cordis.yml'), PROFILE_ROOT_CONFIG)`**
  (`<APP_DIR>\node_modules\@deepseek-ai\dsh\lib\dump-config-*.js` 调
  `profile-boot-*.js` 的 `prepareProfile`,其中 `PROFILE_ROOT_FILENAME = "cordis.yml"`);
  目标 profile 不存在时还会先按模板初始化它(`mkdirSync` + 写文件)。
- 所以**只读沙箱下它必然失败**,原文形如:
  `failed to start packaged dsh: Error: EPERM: operation not permitted, open '…\profiles\<profile>\cordis.yml'`。
- **读法**:这条报错**不是"配置坏了"**,是**权限问题**(写 `cordis.yml` 被拒)。别去改 `cordis.patch.yml`、
  别去重装、别怀疑 YAML 语法 —— 按 §5.0 请求授权,然后**重跑同一条命令**。
- 想避免这一次写:核对改用**文件读取**(`Get-Content <profile>\cordis.patch.yml`)或 `dsh` 的命令行帮助;
  真要打印组合后的配置树,就接受它会写 `cordis.yml` 这一事实。
- 另外两个同族开关:`--dump-default-config` 不解析用户层(用于"用户层坏了"时的恢复诊断),它同样会写 `cordis.yml`。

> **小坑(实测)**:刚初始化的一次性 profile 的补丁文件内容是一行 `[]`(空数组模板)。
> 追加第 3 步之前,若文件里只有这一行 `[]`,先把它删掉再追加,避免数组里多出一个空项。
> 日常 `desktop` profile 的补丁已有内容,直接追加即可。

**为什么启用是"加三行覆盖"而不是改包里的 `disabled`**:`plugin/cordis.patch.yml` 是**包自己的层**,
`<profile>\cordis.patch.yml` 是**用户层、在所有 bundle 层之后应用**(§2.5),同一个 `id` 会被用户层覆盖。
这样 `node_modules` 里的包保持原样、升级不丢,回滚也只需要动一个文件。

#### 备份的「取最新」判据:`CreationTime`,**不是** `LastWriteTime`

第 1 步里那条排序**不能**写成 `Sort-Object LastWriteTime | Select-Object -Last 1` —— 它衡量的是
**源文件最后一次被改动的时间**,不是「哪一次备份最新」。原因是一条 Windows 行为事实:

> **`Copy-Item` 会保留源文件的 `LastWriteTime`。** 新副本的 `LastWriteTime` = 源文件的值,
> 而不是"复制发生的那一刻"。对端实测:两次不同时刻做的备份,`LastWriteTime` **完全相同**。

**正确判据(任选一条,都按"备份动作发生的时间"排序)**:

```powershell
# A) 按创建时间(副本自己的 CreationTime = 复制那一刻)
Get-Item -Path ($patch + '.bak-*') | Sort-Object CreationTime | Select-Object -Last 1 FullName,Length

# B) 按备份文件名里的时间戳排序(推荐,与文件系统元数据无关)
Get-Item -Path ($patch + '.bak-*') | Sort-Object { $_.Name } | Select-Object -Last 1 FullName,Length
```

> **为什么重要**:叠加"`Copy-Item` 被拒是非终止错误"这条,一次**失败的**备份在按 `LastWriteTime` 排序时
> 也能像正常备份一样排在前面 —— 判据坏掉 + 假成功,合起来就是"回滚时才发现没有可用备份"。
> 所以:**排序用 `CreationTime` 或文件名时间戳,并在用之前 `Test-Path` 确认它真的存在、`Length` 非 0。**

### 5.1 启用后你会看到什么(两格判据;实测口径见 §9.1)

装好并重启后,本插件在「设置 → 插件」里**只贡献一张可配置卡片**（与别的插件一致），**不新增设置页左侧导航条目**；侧边栏 tab 是新增接入面，需另装可选依赖 `dsh-better-sidebar`（装了才有，未装无 tab、无报错、不 waiting）：

| 位置 | 预期看到 | 由什么实现 |
|---|---|---|
| **设置 → 插件**(`all` tab,插件清单) | 清单里出现 `dsh-crossnet-link` 这一行,状态**已启用** | 平台自带的 inventory tab,**不需要我们写任何代码**;只要行被装进 profile 就会有(`all` tab 同时列出**未启用**的行并把它们标成未启用,所以装完还没启用时它其实就已经在清单里了 —— 认准"已启用"三个字) |
| **设置 → 插件 → 「可配置插件」tab** | 一张折叠卡片 **`dsh-crossnet-link`**,副标题是**插件目的**(在 A 电脑的 DSH 里驱动通道页面,直接操作 B 电脑上运行的 DSH,两台 DSH 联动 agent 对 agent);点开是**设置表单**(9 个可见控件 + 高级里 5 个,默认折叠;底部「保存 / 放弃」)。schema 库在 profile 侧解析得到,卡片就出现;解析不到只打 warning、卡片不出现(§9.1 实测:本机解析成功、卡片 active) | `settings.plugin.item`,`key` = 设置命名空间 `dsh-crossnet-link`;值走平台服务 `settingsScope`,落在 `<DSH_HOME>\settings.yaml` 的 `dsh-crossnet-link:` section |

**卡片这一格的真实机制(实测澄清,取代原先"`link:` 装法必不出卡片"的推断)**:host 半边对 schema 库
(`@deepseek-ai/schemastery` / `schemastery`)用**受保护的运行时解析**(`await import(specifier)`,try/catch),
而 ESM 解析的起点是 **profile 目录**(loader 从 profile 解析行 specifier),不是 `link:` 目标目录 ——
所以 profile 的 `node_modules` 里有该库(装了其它带 schemastery 的插件时通常就有)就**解析成功**、
命名空间注册成功、卡片**可以渲染**;解析不到时**被 guard 住**(只打一条 warning),卡片不出现,
插件清单行**完全不受影响**。两种结果都是设计内行为。真实装载记录(日志 info/warning + 两格)见 §9.1。

---

## 6. 四步回滚(逐条可粘贴)

```powershell
$repo    = '<REPO>'
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$profile = 'desktop'
$patch   = Join-Path $dshHome "profiles\$profile\cordis.patch.yml"

# ---------- 第 1 步:先停用(首选,不动别的) ----------
# 把覆盖行改成 disabled: true(或直接删掉那三行),然后从 DSH 自带菜单重启:
#   - id: dsh-crossnet-link
#     name: dsh-crossnet-link
#     disabled: true

# ---------- 第 2 步:GUI 异常时,整文件还原 profile patch 的备份 ----------
Get-ChildItem -Path ($patch + '.bak-*') | Sort-Object CreationTime | Select-Object -Last 3 FullName,Length,CreationTime,LastWriteTime
# ↑ 用 CreationTime(或按文件名时间戳)取最新,且用 -Path(通配符要展开;-LiteralPath 一个都不返回):
#   Copy-Item 保留源文件的 LastWriteTime,按它排是坏的(见 §5 的判据说明)
Copy-Item -LiteralPath '<上面列出的那个备份文件>' -Destination $patch -Force -ErrorAction Stop   # 整文件还原,然后重启
# ⚠️ 还原同样是"非终止错误"体质:加 -ErrorAction Stop,并在还原后立刻核对哈希(期望与第 1 步记下的 sha256 逐字节一致)
Get-FileHash -LiteralPath $patch -Algorithm SHA256 | Select-Object -ExpandProperty Hash

# ---------- 第 3 步:从 profile 卸载这个包 ----------
dsh plugin --profile $profile remove dsh-crossnet-link

# ---------- 第 4 步:复原并核对 ----------
# 4a. profile 的 package.json / pnpm-lock.yaml 用第 1 步之前的备份整文件还原(如有)
# 4b. bundles 列表里应不再有 dsh-crossnet-link
(Get-Content -LiteralPath (Join-Path $dshHome "profiles\$profile\package.json") -Raw | ConvertFrom-Json).dsh.profile.bundles
# 4c. 仓库内再跑一次预检(只读),确认骨架本身仍然自洽
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'dsh-crossnet-link\panel\plugin-preflight.ps1')
```

> **为什么第 2 步是"整文件还原"而不是"逐行删掉我加的那几行"**:本机 AGENTS.md 记录过一次真实事故 ——
> 某个第三方插件的**客户端入口引用了当前 DSH 版本里已被删除的客户端包**(`@deepseek-ai/dsh-client-runtime`),
> 结果整个 GUI 变成 `Failed to load plugins` 并卡在恢复模式。那种情况下你需要的是**确定性恢复**:
> 一个已知良好的整文件。这就是第 1 步必须先落整文件备份的原因。

---

## 7. 失败时的第一动作

| 现象 | 第一动作 | 之后 |
|---|---|---|
| 设置里根本没有这张卡片 | 确认覆盖行是否真的生效(`disabled: false`)与 profile 是否重启过 | 再跑 §4 预检;确认 `dsh.profile.bundles` 里有 `dsh-crossnet-link`,并看宿主日志里那条 `settings namespace "dsh-crossnet-link" registered ...` 是 info 还是 warning(schema 库解析不到时是 warning,卡片按设计不出现) |
| 卡片在,点开后只有一行"设置服务不可用" | 这一页拿不到本插件的设置命名空间(极少数情况:非本机页面,或预检 §4 第 4/5 条没通过) | 跑 §4 预检;卡片不写设置时**不会**误报成功,保存按钮也不会亮 |
| **GUI 卡在恢复模式 / `Failed to load plugins`** | **立刻把覆盖行改回 `disabled: true`;若改不动或页面已打不开,就整文件还原 §5 第 1 步的备份,重启** | 恢复后在 `%TEMP%` 的一次性 profile 上按 §8 复现,别在日常 profile 上修 |
| 想彻底消失 | `dsh plugin --profile <profile> remove dsh-crossnet-link` | 再核对 §6 第 4 步 |
| 日志里找不到 `dsh-crossnet-link` 的行 | **层级走错了**:插件的行在 **`<DSH_HOME>\logs\host\`** 子目录里,不在 `<DSH_HOME>\logs\` 根 | 打开 `<DSH_HOME>\logs\host\dsh-YYYY-MM-DD.log` 再搜一次(本机实测:同一天根目录那份约 756 B,几乎没有内容;`logs\host\` 那份 85,630 B、插件行都在里面);仍没有 ⇒ 按 §9.1 的判据先确认行是否真的被装进 profile 并重启过 |

### 7.1 采集器的调用上下文(同一份 `collect.ps1`,两种调用方,判定可能不同)

**先记住这一条**:`src/collect.ps1` 是**同一份脚本**,但**谁来调用它**,会让"同一条探测命令"得到**不同结果**。
文档期望的**权威调用上下文只有一条**:插件路由 → 宿主进程 → `spawn(powershell) → collect.ps1`
(也就是 §7 表格里那条"跑 §4 预检 / 看宿主日志"的路径,以及 §9.1 的两格判据)。**人工在普通窗口里跑的 CLI 结果可用于排障,
但不算权威判定**;在 **agent 工具的受限沙箱会话里跑出来的结果更不算**(见下表)。

| 调用上下文 | 谁在跑 `collect.ps1` | 对端实测:同一条 `tailscale ip -4` |
|---|---|---|
| **权威**:插件路由 → 宿主 → spawn | DSH 宿主进程 `ctx.subprocess.spawn(...)` 拉起的 PowerShell 子进程 | **exit 0**(`TAILSCALE_CLI_LAYER` 报 pass) |
| 受限:agent 工具沙箱 | agent 的工具链在会话沙箱里直接执行命令 | **`open \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled: Access is denied.`(exit 1)** ⇒ 同一项只能判 `unknown` |
| 参考:人工普通窗口 | 用户自己开的、未受限的 PowerShell | 与权威路径一致(exit 0);**但它取证成本高、不可自动复现,只作旁证** |

**为什么两个上下文会不一样**:两条路径的**沙箱层级不同** —— agent 工具链受命名管道 / 权限限制,而宿主 spawn 出的子进程不受同一层限制。
这是**调用方之间的差异**,不是脚本坏了,也不是"机器状态变了"。(对端标记为【推断】;本仓库引用其**现象**,
不把它当已证实的机制 —— 见 §9「未验证清单」。)

| 维度 | agent 沙箱里调用 | 宿主 spawn 调用(**权威**) |
|---|---|---|
| 命名管道 / 提权探测(如 `tailscale ip -4`) | 可能被拒 ⇒ 该项 `unknown` | 能拿到真实判定 |
| 文件、端口、注册表读取 | 一般可用 | 可用 |
| 结果口径 | **不能**当验收判据 | 本文所有判据以它为口径 |

**做法(写死)**:

1. **报告与验收一律以权威上下文为准** —— 以插件路由跑出来的报告(或宿主日志)为判据;
2. 在 agent 沙箱里跑出来的结论,**只能当线索、不能当证据**:比如 `TAILSCALE_CLI_LAYER = unknown`,
   那说的是**这个调用方探不动**,不是"对端没登录 Tailscale";
3. 两边的判定**不一致时不要互相覆盖**:先报告"哪个上下文跑出来的",再解释差异从哪来(上表);
4. 想在沙箱里也拿到可信的 CLI 层判定:要么换到宿主 spawn 的那条路(启用插件后打路由),要么在普通窗口人工跑一次。

---

## 8. 首次验证请用一次性测试 profile

**不要第一次就上你每天的 `desktop` profile。** 这个骨架的 host/client 半边**从未在真实 DSH 里跑过**
(§9),第一次验证的价值就在于"用最便宜的代价拿到第一次运行证据":

```powershell
$repo = '<REPO>'
$plugin = Join-Path $repo 'dsh-crossnet-link\plugin'

# 1) 建一次性 profile:首次执行 dsh plugin --profile <新名字> 会按模板初始化它
#    (证据:<APP_DIR>\node_modules\@deepseek-ai\dsh\lib\plugin-Ddi42qoW.js:101-107)
dsh plugin --profile plugin-test add ('link:' + $plugin)

# 2) 让它用另一个端口引导,避免和日常 DSH Desktop 的 web 端口打架
#    先看这个 profile 组合出来的 webServer 行叫什么、当前端口是多少:
dsh --profile plugin-test --dump-config | Select-String -SimpleMatch 'webServer' -Context 0,6
#    然后在该 profile 的 patch 层给那一行覆写 config.port(0 = 让系统分配空闲端口;
#    证据:<APP_DIR>\node_modules\@deepseek-ai\dsh-host-webserver\lib\index.js 的 Config:`port: z.natural().max(65535).required()`)
#    编辑 <DSH_HOME>\profiles\plugin-test\cordis.patch.yml,再:
dsh --profile plugin-test

# 3) 验证完就整条拆掉
dsh plugin --profile plugin-test remove dsh-crossnet-link
```

一次性 profile 不碰你日常 profile 的 `package.json`、不碰日常那套设置与会话数据;坏掉直接删目录重来。

---

## 9. 未验证清单(边界,不粉饰)

1. **真实加载记录只有一次,在真实 DSH 上(2026-09-25)**。§9.1 是本仓库的第一份真实装载观察:
   「设置里出现分区、插件清单行已启用、卡片格的条件与实测」按 §9.1 的日志原文与座位证据核实;
   它仍然不替代「每台机器、每种环境各跑一次」—— 在你的机器上按 §5/§8 跑一次才算你这台机器算数。
2. **host 路由的运行时行为未验证**:同源校验、body 上限、`webServer.register` 的 prefix 选择,
   都只做了静态证据(§2.4)与本仓库的静态断言(§4),没有真机运行记录。
3. **client bundle 的手写性**:本仓库没有 tsdown/tsc 工具链,`plugin/lib/client.js` 是按真实 bundle
   的格式手写的单文件。它能被 `__ModuleLoader__.load` 接受这一点,只有把行启用后由页面回答。
   为降低风险,预检钉住了"共享正文逐字节相同"与"require 只允许平台 seed"两条。
4. **`node --check` 未执行**:本机 `node` 不在 PATH(实测 3 条 `[SKIP]`),所以"能作为普通 JS 解析"
   目前只有正则级静态断言,不是解析器级证明。
5. **多 profile / 多版本组合**:本文只覆盖"一个 profile、本机这一版 DSH"的口径;Win10/Win11 四种组合
   的适配属于另一条任务线,不在本阶段结论内。
6. **`<APP_DIR>` 下的行号**来自本机这一版安装镜像;DSH 升级后行号可能平移,文件名与结构才是判据。
7. **插件页卡片:实测澄清 —— schema 库按 profile 侧解析,解析得到卡片就出现**。卡片能否渲染取决于两点同时成立 ——
   ①host 半边成功注册了带字段 schema 的命名空间 `dsh-crossnet-link`;②client 半边把 `settings.plugin.item`
   以同名字符串为 `key` 注册上。第①点依赖 **schema 库能否被运行时解析**
   (`@deepseek-ai/schemastery` / `schemastery`),而解析的起点是 **profile 目录**(loader 从 profile 解析行
   specifier),**不是** `link:` 目标目录:本机桌面 profile 的 `node_modules` 里有该库(其它插件带入),
   实测**解析成功、命名空间注册成功、卡片座位 active**(§9.1)。在一个没有该库的 profile 上,解析会失败,
   行为是**已知且刻意的**(打 warning、不注册、卡片不出现、其余功能照常),已被 guard 住。
   判断口诀:分区出现 = 骨架加载成功;清单里出现该行 = 行真的被装进 profile;卡片出现 = 上面两点都成立
   (其中第①点取决于 profile 能否解析 schema 库)。真实装载时的日志观察见 §9.1。
   **v0.4 之后尚未实测的部分**:卡片里点「保存」→ 平台设置服务 `settingsScope` → `<DSH_HOME>\settings.yaml`
   的 `dsh-crossnet-link:` section → 采集器参数,这条链路目前只有静态与库级验证(schema 默认值、白名单映射、
   两份 client 正文一致性都用真库/脚本跑过),**没有真实页面上的保存记录**;§9.1 那次装载发生在 v0.4 之前,
   记录的是"座位能不能渲染",不是"设置能不能存"。真正装到一台机器上时,第一件要看的证据就是
   `settings.yaml` 里有没有 `dsh-crossnet-link:` 这段。
8. **退出码契约的自证范围**:`-SelfTest` 覆盖的是**静态**故障(入口缺失 / 行 id / 行 disabled / 共享正文漂移 /
   卡片座位消失 / 文档缺失)与基线;真实加载期的失败(路由注册失败、采集器超时、命名空间被占用)不在它的覆盖里。

### 9.1 第一次真实装载观察(2026-09-25,真实 DSH,日常 profile)

**做法**:按 §5 三条命令在**真实 profile** 上安装(备份 → `dsh plugin add link:` → 追加启用覆盖行),
然后从 DSH 自带菜单重启 DSH。

**装载日志**(重启后;`[I]` = info,`[W]` = warning):

```text
[I] [dsh-crossnet-link] dsh-crossnet-link: read-only posture route ready at /dsh-crossnet-link/api (collector <REPO>\src\collect.ps1)
[I] [dsh-crossnet-link] dsh-crossnet-link: settings namespace "dsh-crossnet-link" registered (the plugins-page card can render)
```

> 这两行是 **v0.3 那次装载的原文**(实测记录,不改写历史)。v0.4 起第二行的措辞变成
> `... registered with this plugin's check parameters (the plugins-page card can render and save them)`,
> 判断方式不变:**info = 命名空间注册成功 = 卡片可以渲染;warning = schema 库没解析到 = 卡片按设计不出现**。

两条都是 **info,没有 warning** —— 包括 §5.1 说的 namespace 注册:它**成功**了(profile 侧解析到了 schema 库),
所以卡片这一格在本机是**渲染前提成立**的。§2.6 的 guard 没有触发。

**两格观察**:

| 格 | 判据 | 实测 |
|---|---|---|
| ① 插件清单行 | 组合配置里该行 `disabled: false`;清单由平台 inventory 列出 | 行已装进 profile 且 `disabled: false`(`--dump-config` 原文:该行 `patched by <DSH_HOME>\profiles\<profile>\cordis.patch.yml`) |
| ② 可配置插件卡片 | `settings.plugin.item` 活注册 + host 命名空间注册 | 卡片座位 `registrant: dsh-crossnet-link, key: dsh-crossnet-link, order: 100, active: true`;host 日志确认命名空间注册成功 → **渲染的两个前提都成立** |

> 说明:早期版本还额外注册过一个独立侧边栏分区(`settings.section`),后按「与别的插件一致」的要求
> 移除 —— 现在 DSH 设置页里只贡献这一张可配置卡片，不新增设置页左侧导航条目；
> 侧边栏 tab 是新增接入面，走可选依赖 `dsh-better-sidebar`（装了才有，未装无 tab、无报错、不 waiting）。

**结论**:真实装载一次通过,两格全中;本机日志是 **info 不是 warning**。
之前「`link:` 装法必不出卡片」的推断被实测**推翻**:ESM 解析起点是 profile 目录,profile 里有 schema 库就出卡片。
保留的只有一句:**卡片一格取决于 profile 能否解析 schema 库**;解析不到时 warning + 卡片不出现(guard 不变),
插件清单行不受影响。

首次观察还暴露了一个编码缺陷(面板中文乱码):`collect.ps1 -AsJson` 的输出编码跟随进程控制台,
宿主子进程里是 GBK 而 host 按 UTF-8 读。已修:JSON 输出改为固定写 UTF-8 字节,不改任何判定。
