> 来源:本文原样搬运自旧版 README.md 的 §18(2026-09-24 版)。2026-09-25 起 README 精简为十个章节,该节整体移入本文件,正文未改。文中出现的 §N 一律指旧 README 的节号。
> 路径说明(2026-09-26 补,**不修改 §18 原文**):§18.1 里那三条 `verify.ps1` 命令用的是**当时那台开发机**上
> 「项目级安装」的相对路径 `.dsh/skills/dsh-remote-tailnet/scripts/verify.ps1`;仓库里同一份脚本在
> `docs/install/skill/dsh-remote-tailnet/scripts/verify.ps1`,照 `docs/install/link-guide.md` 或 skill 自己的
> `README.md`「怎么用」把它复制到 `<工作区>\.dsh\skills\dsh-remote-tailnet\` 之后,那三条命令原样可跑。
> 命令里的 `<PEER_IP>` 本就是对端地址占位符,无需改。

## 18. 证据链:本任务实测、引用自其它任务、仍未验证

三类,从不混用。「实测」= 本任务跑了那条命令并看到输出;「引用」= 原样复用另一个任务的结果,强度不超过那个任务的证据;「未验证」= 还没有人测过。

### 18.1 本任务(t9)实测

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
# verdict: CLEAN (0 blocking finding(s))
# {"root":"…","files":85,"blockedHits":0,"credValueHits":0,"wordHits":194,"encodingFailures":0,
#  "lineEndingNotes":1,"binaryFailures":0,"forbiddenCode":0,"forbiddenDoc":2,"missingIgnores":0,
#  "missingMarkers":0,"unclassified":0,"blockingTotal":0,"verdict":"clean"}   exit 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
# 443 -> connected (189ms)   135 -> timeout (5006ms)   5357 -> timeout (5005ms)
# VERDICT 全通:443 connected,其余 2 个口均 timeout(ACL 隔离成立)      EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 3 -IntervalSeconds 5
# 18:30:36 #1 connected 194ms / #2 203ms / #3 194ms  ->  SOAK total=3 connected=3 failed=0
# VERDICT 全通:窗口内全部 connected                                   EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 11 -IntervalSeconds 30
# 11 rounds, window 2026-09-24 18:33:16–18:38:18 (305 s)
# connected 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 / 186 ms
# SOAK total=11 connected=11 failed=0
# VERDICT 全通:窗口内全部 connected                                   EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1
# ALL PASS: 7 cases, 0 failed assertions                              EXIT 0
```

- 对端探测,5 秒超时,`[Net.Sockets.TcpClient]`:**18:25 timeout**、**18:30 connected**(两次都引在 §17.5)。
- 11 轮 soak,在短 soak 之后跑:**11/11 connected、failed=0**,窗口 **305 秒**(18:33:16–18:38:18),各轮 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 / 186 ms,`VERDICT 全通:窗口内全部 connected`,**EXIT 0**。与上面那次 15 秒运行一样,按**窗口有限的观测**引用 —— 两者都没有说链路「稳定」。
- 检查项清单:`src/collect.ps1` 里 `New-Check` 出现 **26** 次(26 个检查项),`panel/prereq-manifest.json` 的 `items` = **13**。
- 发布集清单:门禁的默认根覆盖代码目录(`src/`、`i18n/`、`tests/`、`panel/`、`tools/`、`plugin/`)加上已发布的文档与根文件;它会打印实时文件数,所以这一行不冻结任何一个数字。`plugin/package.json` **存在**(那就是常驻插件包,§15);而仓库**根**没有 `package.json`(测试路径上没有任何东西需要它 —— 见 §19)。
- §17.1 用到的 skill 文件状态(两份副本逐文件比 SHA256:11 对 11 个文件,9 个相同,本任务改过的 `references/verify.md`、`references/troubleshooting.md` 不同 ⇒ 正好是同步命令要补的缺口)。
- §17 时代的编辑之后重新解析了 skill 脚本:`verify.ps1` 与 `server-setup.ps1` 都报 `errors=0`(`Parser::ParseFile`)。

### 18.2 引用(其它任务的命令与结果)

按来源任务归并(英文原文 §18.2 是逐行对照表,这里合并同类项,任务号一个不落):

| 来源任务 | 被引用的结论 |
|---|---|
| t7 | 客户端侧端到端判定 **pass**(17:36 对端 `:443` connected 860 ms,命令 `verify.ps1 -ServerIp <PEER_IP>`) |
| t8 | 安全评审结论是 **needs_revision**(不是通过),并带 findings 清单 |
| t16(10/10)、t19(5/5)、t17 复审 | 上述 findings 修完之后的逐条处置表与复审结果 |
| t23 | 离线套件全绿:**52 cases / 52 passed / 0 failed / 0 xfail held / 0 xpass / ALL PASS**,exit 0 —— 这是 `xfail` **和** `xpass` 同时为 0 的第一次运行;同时刷新了 `SERVE_PRESENT` 语义(证据只来自可读的 `serve status` proxy target,读不出 ⇒ unknown) |
| t12(+ t24 把 `panel/`、+ t39 把 `tools/` 加进发布集) | 发布集卫生:`verdict: CLEAN`、0 阻断;t23 的两个扫描范围也一致 —— 门禁范围之外的每一处真实命中都是允许清单里的替换值或有记录的夹具,且两份小结都没有冻结文件数 |
| t24 | `panel/` 属于已发布发布集;许可已定(README §8/§12、`.gitignore` 取消排除、门禁默认根) |
| t25 | `docs/collect.md` 的 `SERVE_PRESENT` 文案刷新归它(代码/判定语义已经是 t23 的) |

### 18.3 未验证 / 在这里无法测量

- **一个实时的 Windows 11 客户端** —— 没有这样的机器,所以组合 B 与 D 沿用 Win10 客户端的代码路径而没有实时跑(见 §16)。
- **Win11 → Win11 端到端** —— 只有夹具覆盖(`tests/fixtures/win11-server.json`)。
- **一块被归到 `Public` profile 的网卡** —— 只能从规则的 `Profiles` 字段推导;它在 Public 机器上的静默失败后果**没有**实测,所以绝不能被报成「已验证」。
- **服务端侧的 HTTPS/证书判定** —— 受限环境里 schannel 不可用,所以 HTTPS 判定只存在于能跑 OpenSSL 探测的地方。
- ~~**一次成功的动态包激活**~~ —— **已移出本清单**:2026-09-24 在一个普通工作区级会话里实测(`rtgpnl-3` / `pkg-6` → `awaiting-approval` → 点勾 → run **completed**,面板出现在设置导航里;§14.1 与 §17.2 把这条正面路径与被实测的成员会话失败并排放在一起)。仍然未验证的只是它在**别的机器上**的失败形态。
- **常驻插件包** —— 已随 `plugin/` 发布,挂载行是 `disabled: true`,而且从未在真机上启用过(§15;未执行的清单见 `docs/install/plugin-package.md` §9)。

### 18.4 连通性:那次对端掉线影响了什么、没影响什么

17:44 到约 18:30 之间对端不可达,所以那个窗口里两项「双机」检查没法重测。**没有任何一项因此被判失败,也没有任何一项被糊过去**:对端不在时,离线那一层(拿夹具跑的 26 项采集器、13 项前置件检查器、`run-fixtures` 套件、卫生门禁)仍然完全可测 —— 这正是离线接缝的意义 —— 两项双机检查被如实记为 `timeout`,而不是记成某个判定。18:30 对端恢复应答,三态与一次短 soak 被直接实测(§18.1)。仍然开着的是:本机之外的机器上的客户端侧 MagicDNS/HTTPS 两项(§17.5、§18.3)。11 轮 soak 现在**不在**这个清单里了 —— 它已实测(§18.1)—— 但链路观测属于它被测的那台机器与那个环境,所以重置、换客户端或换 tailnet 都意味着操作者要重跑一遍(§17.5)。
