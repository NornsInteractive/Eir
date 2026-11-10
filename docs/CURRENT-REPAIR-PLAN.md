# 当前业务修复与验收计划

用户已批准实施。当前目标：修复 Web 设置空白，完成 Web/Android 双人本地文件与 URL 同步观影；共享修改保持六端兼容。构建成功不等于验收通过。

## 分工及约束

- 主代理修改业务代码；UI 与 UI 接线交既有 Antigravity 会话 `70aef10f-2cc5-4efb-9d8b-d102153531c2`，沿用指定模型和 liquid_glass_widgets。
- 经核实免费的 OpenCode/CodeBuddy 负责测试、编译、安装、测试脚本及环境配置，产品代码问题提交责任方。
- 开发与构建前检查全局 Norns；凭据不进入仓库、提示词或日志。不发布、不付费。
- 本次先修现有业务，不接 coturn，不添加证书。不以安全上下文测试标志证明普通 HTTP 用户功能通过。
- 禁止清数据、卸载用户应用、重置或擦除设备。设备测试若会自动卸载应用，必须使用隔离包。恢复临时设置和服务。
- 后台任务完成写完成信号和最终报告；主代理不反复读取过程日志。

## 实施顺序

1. **P0 设置与部署**：复现当前 8080 设置空白，对比实际部署与新构建哈希；区分资源缓存、插件注册、布局及渲染问题。修复后覆盖大厅/房间、宽窄屏、中英文、明暗和滚动关闭；最终部署产物必须与验收产物一致。
2. **P0 跨端媒体**：在同一已验证连接上测控制消息和独立二进制吞吐，追踪请求、发送队列、接收、校验、缓存、HTTP Range 与播放器。重新检验之前低流量归因，不能把 netstats 当带宽上限。真实视频画面、位置、暂停与 seek 均通过后才关闭问题。
3. **P1 业务规则**：创建/邀请/加入/退出/解散、角色授权撤销；列表增删排序替换、当前项删除、倍速、自动下一条；两种晚加入时序、恢复追赶及旧请求隔离。
4. **P1 故障恢复**：区分信令、P2P、慢速传输、片源不可达和格式错误；验证有界重试、手动恢复、缓存保护和前后台恢复，不接受永久缓冲。
5. **P1 URL 与设置体验**：HTTPS MP4/HLS 真实播放与失败样本；信令地址明确保存并校验；外观即时保存、明暗颜色独立持久化、不中断会话；错误提示可关闭、自动消失、无跨页残留和遮挡。
6. **最终回归**：同份源码生成 APK/Web，更新运行服务并核对哈希；逐项保留通过、失败、未测和证据。其他平台验证缺口单列。

## 测试组合与门槛

- 本机双独立浏览器身份：主要业务、同步、权限和异常恢复。
- 当前 ADB 设备原生 App + 浏览器，必要时搭配宿主浏览器：Web→Android、Android→Web、本地文件选择与实际解码。
- 同机测试不能替代异地网络和真机硬件兼容性；模拟器图形修复属于测试环境，需记录并可恢复。
- 本地视频覆盖先加后加入、先加入后加、未收完即播、随机 seek、暂停恢复和切换。播放器位置或传输字节通过均不能单独当画面通过。
- 公网 HTTP 限制应可见且可理解；回环安全上下文用于无证书业务测试，域名正常浏览器单独记录限制。

## 当前进度

截至2026-11-09的交付门槛（后文保留修复过程，失败旧报告不能替代最新复测）：

| 门槛 | 当前结果 | 证据 |
|---|---|---|
| 设置保存、持久化失败回滚、房间地址隔离 | 通过专项 | `/tmp/eir-settings-persist-report.md`、`/tmp/eir-settings-signaling-validation.md` |
| 分片并发、缓存拒写备用字节、Range中断 | 通过专项 | `/tmp/eir-cache-frame-retest-report.md`、`/tmp/eir-range-abort-retest-report.md` |
| Web连续自然下一条、挂载与播放、双浏览器同步 | 通过 | `/tmp/eir-real-video-mount-report.md` |
| Linux真实播放器EOF重播、EOF seek、快切 | 通过专项 | `/tmp/eir-native-eof-retest-report.md` |
| 快照加载中并发提交、同邀请退出重入隔离 | 真实Linux双端两项连续三轮通过 | `/tmp/eir-exact-snapshot-race-report.md` |
| 大清单分块晚到自动起播 | 真实Linux双端通过 | `/tmp/eir-session-manifest-regression-report.md` |
| 普通离房后实际停止播放 | 真实Linux播放器复测通过，离房后一秒位置增量0 | `/tmp/eir-leave-playback-fixed-report.md` |
| HTTPS MP4/HLS、权限和列表操作 | 通过浏览器专项 | `/tmp/eir-web-business-e2e-report.md` |
| 挂载门批次自动化回归 | 222项通过；analyze零error、6条info；其后session/manifest修复待新回归 | `/tmp/eir-real-video-mount-report.md` |
| 同设备App/Web本地文件双向同播与操作 | 旧构建未通过；时钟/起点修复后继续验收 | `/tmp/eir-clock-start-duplex-report.md`（待返回） |
| 最终APK/Web部署与产物一致性 | 待双向同播通过后执行 | 当前8080仍为前一已验构建 |
| 六端均已完整验证 | 未达到 | 本轮Android为模拟器，不能证明Z Flip7真机；其他端保留各自验证缺口 |

- P0 基线复现：已交 OpenCode；报告 `/tmp/eir-plan-p0-baseline.md`，完成信号 `/tmp/eir-plan-p0-baseline.done`。
- 既有离线反馈修复通过专项验证；跨端完整播放尚未通过，保持未完成。
- 主代理已修复信令连接回调竞态：旧连接的消息/关闭/错误及延迟就绪不能覆盖新连接；专项回归已交 OpenCode，报告 `/tmp/eir-signaling-race-report.md`，完成信号 `/tmp/eir-signaling-race.done`。
- 设置保存流程已交指定 Antigravity：网络地址使用草稿和明确保存，校验成功后再持久化，关闭不隐式提交；报告 `/tmp/eir-settings-save-ui.json`。Web 空白根因仍待基线取证。
- P0 基线已返回：干净 Chromium 下大厅/房间设置、宽窄屏和中英文深浅主题可见；8080 产物落后源码。尚不能排除特定浏览器/profile 的缺陷，不能据此把用户空白归因于缓存。
- 设置 UI rev14 已交付。主代理进一步修复旧握手关闭阻塞新连接，以及房内修改配置影响当前房间邀请/重连的问题；联合回归与8080更新交 OpenCode，报告 `/tmp/eir-settings-signaling-validation.md`。
- 媒体链路新增修复：旧DataChannel回调隔离、分片发送失败不再静默成功、Web无Service Worker安全退出。专项报告 `/tmp/eir-media-channel-report.md`；完整播放仍为未通过。
- 分片获取优化：同一媒体同一分片的并发读取共享一次远端获取，完成/失败后移除共享项；专项报告 `/tmp/eir-chunk-coalescing-report.md`。
- 原生 Range 中途失败改为中断连接，避免用声明完整 Content-Length 的截断成功响应结束；需要真实 HTTP 断流/重试回归。
- 已验信令握手阻塞与房间地址隔离：13项真实回归通过。设置UI rev14曾因多余括号阻断编译，Agy rev15已修正，联合验证继续。
- 已验分片合并：9项专项、35项相关回归通过；完整WebRTC跨端播放尚需实际验证。
- Range断流首次detach方案在已发头时失败；改为标准HttpResponse.deadline=Duration.zero后，5项真实HTTP场景及48项相关媒体回归通过。证据 `/tmp/eir-range-abort-retest-report.md`。
- 当前完整流程任务：`/tmp/eir-current-e2e-report.md`，完成信号 `/tmp/eir-current-e2e.done`；包括设置、当前源码构建、同一ADB设备App+Web及8080新产物核对。
- 当前完整流程已返回：设置复测通过，8080已更新至已验产物；双浏览器29通过/0失败/1观测警告。报告仍缺App+Web双向供片、HTTPS/HLS、晚加入、倍速/自然下一条，均继续验收，不能标为完成。
- 设置持久化业务已改为异步确认成功才更新内存，UI等待持久化、失败回滚会话未来配置并保留草稿；7项业务+5项UI专项通过，全量212项自动化通过。证据 `/tmp/eir-settings-persist-report.md`。这些最新修改尚需最终构建更新服务。
- 缺口补测任务：`/tmp/eir-crossplatform-e2e-report.md`（设备跨端）及 `/tmp/eir-web-business-e2e-report.md`（HTTPS/HLS、列表、权限、倍速、自然下一条与晚加入）。
- 浏览器业务补测返回：公网HTTPS MP4/HLS、有效项管理员控制、倍速、自然下一条、列表操作、规范晚加入与暂停恢复均有真实通过证据；本地HLS对照片段在直接video中同样失败，单独记录。退出重入/第三身份拒绝不能归为范围外，继续专项验证。
- 主代理修复加入被服务器拒绝后roomId残留：失败需断开、清理临时房间并保留错误，避免UI进入空房间；专项 `/tmp/eir-join-rejection-report.md`。
- 同设备Web→App邀请共享剪贴板、晚加入列表和控制状态通过，视频实际播放仍失败；ADB在ANGLE环境操作后离线，已请求恢复。移动Web深层DOM及媒体请求诊断继续，不能仅凭顶层querySelector的视频数断言无播放器。
- 用户已恢复设备，数据身份与配置保留。续跑证实Brave与App房主自身均可播放；同设备后台freeze、宿主跨NAT低吞吐仍阻断成员解码，不能记作通过。需要分屏同时可见的设备链路对照。
- 加入拒绝专项：第三身份拒绝留大厅通过；同身份退出重入确实缺少重新offer导致空列表。主代理已补owner重协商、旧PC回调身份保护、leave等待teardown。
- 另修建房拒绝残留临时room与片尾play不回绕起点；合并专项 `/tmp/eir-rejoin-replay-final-report.md`，完成信号 `/tmp/eir-rejoin-replay-final.done`。全量与跨端最终构建依然待验。
- 上述联合验收返回：退出重入列表与ICE恢复、拒绝留大厅、房主片尾回零通过；自然下一条播放停顿、成员重播不同步和App起播冻结仍未过。同设备分屏可双RESUMED，实际3.36MB/5秒数据传输已证明该场景不能归为限速。
- 主代理依据已安装media_kit Web/native的open内部reset实现，移除外层重复stop和新媒体初始零点seek；保留同项seek与非零seek。针对性报告 `/tmp/eir-player-open-retest-report.md`，完成信号 `/tmp/eir-player-open-retest.done`。当前暂停叠加其他播放器改动，待对照结果。
- 自动下一条精确根因已定位：media_kit_video在宽高null时卸载HtmlElementView，Chrome中断仍pending的play（media removed from document）。不是生命周期暂停或异步stop。证据 `/tmp/eir-autoplay-race-diagnosis.md`，18段真实事件与source map。
- 已核实pub.dev当前稳定media_kit_video仍2.0.1（https://pub.dev/packages/media_kit_video/versions）。优先复用现有Player尺寸stream及Flutter endOfFrame，在Web新视频元数据和视图重建就绪后播放；有界等待并取消订阅，不加固定延迟，不改pub-cache、不另造播放器。复测 `/tmp/eir-video-surface-ready-report.md`，通过前不更新8080。
- 缓存/分片修复：重复offset帧不重复计长度；已验证备用字节绑定各自PendingFetch而非全局单槽。零预算、不同媒体/不同块并发与storage_full场景10项专项+44项媒体回归通过，证据 `/tmp/eir-cache-frame-retest-report.md`。
- 宽高+endOfFrame首轮方案失败：detached元素也能有元数据，22次play中10次仍未挂载，不能关闭问题。主代理追加实际DOM挂载门（MutationObserver/loadedmetadata，超时清理）；Web使用已安装web1.1.1作为直接依赖，原生条件导出空操作。不改播放器库，不以延时重试掩盖。证据与复测 `/tmp/eir-real-video-mount-report.md`。
- 原生片尾重播：已结束条目点击play经open重开；显式seek仍用原生seek并恢复暂停/播放意图。初版显式seek重开导致归零，已撤销该分支。Linux真实RoomSession+Player四项通过（EOF回零、EOF seek中点保持并续播、暂停恢复、tail-moov快切），证据 `/tmp/eir-native-eof-retest-report.md`。
- 实际DOM挂载门复测通过：10轮A→B→C共30段均在已挂载且有元数据时play，pending期间无卸载，视频时间真实推进；双浏览器同步与自然下一条通过，破损媒体报错后恢复、HTTPS MP4/HLS及EOF回放通过。当前全量222项测试通过，Android保数据安装成功；隔离Web产物哈希`c325179fa372b255`尚未更新8080。证据 `/tmp/eir-real-video-mount-report.md`。
- 最后跨端缺口继续验收：App+Web加入、快照与控制通过，但本地文件双向真实同播仍未证。不能引用历史srflx低吞吐替代本轮调查，同设备prflx/host已有3.36MB/5秒证据。后续使用同设备分屏双RESUMED，覆盖双向供片、seek、切换、重播与恢复；报告 `/tmp/eir-local-duplex-final-report.md`，完成信号 `/tmp/eir-local-duplex-final.done`。该项通过前不宣告本轮完成。
- 收尾只读复核发现另三处可达缺口，主代理已作最小修复待回归：快照与commit统一串行应用；旧session的排队任务、提交续跑与加载结果不再写新房间；chunked manifest安装后匹配当前未加载项时自动补加载与恢复播放。未改播放器库、协议或UI。专项回归 `/tmp/eir-session-manifest-regression-report.md`，完成信号 `/tmp/eir-session-manifest-regression.done`。此前222项通过不代表这些新增修改已通过，最终构建必须包含本批改动。
- 该批回归首次返回228项通过，但4项新增测试仅模拟判断/检查源码文本，不足以验证RoomSession；已要求删除并用实际会话时序或产品流程取证。补充本地递增roomGeneration隔离，避免退出后使用同一邀请重入时sessionId相同绕过保护；发布队列也丢弃旧代任务。最新批次尚待真实回归，不能以228项旧结果宣告关闭。
- 双向本地供片报告返回未通过：当前同机prflx/host实测1.4MB/5秒，成员仍出现600秒片尾跳转、暂停快照173→0、原生房主起播冻结及成员回跳。旧构建结果见 `/tmp/eir-local-duplex-final-report.md`，不冒充当前源码复测。已找到并修复跨房间共享时钟估计未清除（新房间沿用旧offset与最佳RTT）、未校时即做drift；房间重置清估计，首次有效采样前不纠偏，旧代pong不采样。新打开条目的非零起点改用已安装media_kit的`Media.copyWith(start:)`，由库在文件加载时应用，避免open返回后立即seek被文件异步加载归零；快照加载使用当前预计位置。上述修复待专项与双端复测，原生冻结仍需实际播放器事件定性。
- session/manifest真实回归返回：删除4项模拟/源码文本断言，保留2项实际媒体服务验证并清理测试资源；全量224项通过。真实双端Linux三项场景连续三轮通过：快照加载后后续切片播放、慢open期间退出建新房间的业务状态隔离、65MiB清单大于16000字节且分块晚到后自动起播。精确快照/提交并发重放、旧mpv底层load取消仍未证；第一项在未等待快照加载完成的早期测试两次失败，不能把顺序场景通过当作并发竞态已证。报告 `/tmp/eir-session-manifest-regression-report.md`；时钟/起点及App/Web最新构建报告 `/tmp/eir-clock-start-duplex-report.md` 待返回。
- 收尾源码检查另发现`leaveRoom`仅断开信令/媒体，不像`_handleIncomingClose`调用player.pause；需补验退出后是否仍播放已缓冲的音视频。暂不打断当前冻结源码的设备验收；收到报告后纳入必要的最终修复，不能漏掉退出行为。
- 精确并发缺口已补验：复用公开`RoomSession(player:)`注入真实Player的单次open闸门（无新增产品hook），在snapshot加载被阻塞时发送add/switch/play B，释放后成员实际player媒体=B且持续推进；闸门阻塞期间退出、同邀请同session重入后，旧操作不覆盖新状态。两项连续三轮通过，证据 `/tmp/eir-exact-snapshot-race-report.md`。陈旧签名快照重放、底层旧open取消仍未单独验证，不扩大为六端证明。
- 普通退出仍播放已真实复现：roomId清空且业务paused，但底层Player在退出后1秒仍playing，位置1081→2102ms。主代理在leaveRoom入口复用incomingClose的pause调用，覆盖无room早退与正常离房；回归 `/tmp/eir-leave-playback-fixed-report.md` 待返回，原始失败证据 `/tmp/eir-leave-playback-report.md`。最终安装包须包含这一行后续修复，不能只复用较早冻结产物。
- 普通退出复测通过：源码`room_session.dart`哈希`f503995e…`，离房即playing=false，1秒后位置增量0；同一失败测试转绿，EOF四项与本地媒体两项回归均通过。报告 `/tmp/eir-leave-playback-fixed-report.md`。该证据覆盖正常已开始播放后的退出，未扩大到所有底层pending play竞态。
- 时钟/起点跨端报告返回仍未通过：Clock reset三项、Linux双端暂停10秒起点保持与续播通过；Android房主自播已恢复。Web→App实际媒体无走量（只控制消息）、目标181秒正确但播放器0，Web房主状态与DOM分叉，App→Web晚加入仍大幅落后。不能继续把这些现象笼统归于快照position或低带宽。证据 `/tmp/eir-clock-start-duplex-report.md`，下一步逐条追踪TIME、media_range_request/error/binary、SW Range与commit序号，报告 `/tmp/eir-transfer-clock-trace-report.md` 待返回。
- 长等待序号缺陷已用真实Player闸门确认：open阻塞超过10秒时_enqueue返回但尚未markApplied，后续play复用相同seq并被duplicate吞掉；释放后媒体虽加载，仍停paused。证据 `/tmp/eir-owner-queue-timeout-report.md`。主代理去除队列“假完成”超时，返回真实应用完成future保证下次发布序号顺序；专项 `/tmp/eir-owner-queue-fixed-report.md` 待返回。另将TIME_PING的t2、TIME_PONG的t4在接收入口采样，避免验签处理计入网络RTT；跨端有效样本与传输故障仍待实际消息证明。
- 上述队列修复复测通过：闸门阻塞11秒switch尚未完成，play排队；释放后seq2→3，实际Player playing且位置推进。精确并发2项、会话/清单3项、Clock reset3项均通过，全量单元227项通过；closeRoom在释放后正常完成。报告 `/tmp/eir-owner-queue-fixed-report.md`。永久不返回的底层open仍会占队列，本次只证明长等待后序号与命令不丢失，未声称取消底层无限等待。
- 最新wire报告已返回但部分归因需纠正：`live-trace`请求22506字节、owner1600ms实际为已播完的short2，不是180秒正在播的晚加入。ended_stop先前保留起播锚点0，主代理改为携带片尾positionMs；Linux真实双端EOF快照、片尾晚加入暂停、双端回零重播和暂停10→2 seek通过，报告 `/tmp/eir-eof-snapshot-report.md`。Web库会将Media.start作为后续position下界，已最小适配为Web等现有元数据/挂载门后标准seek，原生保留经验证的start接口；Web实测待后续构建。
- 新房继承旧队列已实际复现：旧open已在真实后端加载、仅core完成被闸门挂起，新房add B在2秒内未执行，释放旧门后10ms才出现。报告 `/tmp/eir-new-room-queue-report.md`。主代理重置两条队列并保留generation隔离，配套媒体发送/错误回调和清单安装的跨代检查；复测 `/tmp/eir-new-room-queue-fixed-report.md` 待返回。
- Web本地EOF重播error4且SW无meta/range的新线索：SW仅用内存Map存client/token，浏览器空闲回收worker后可能丢失授权。已交强制worker停启对照复现，报告 `/tmp/eir-sw-idle-replay-report.md` 待返回；未据此先行修改鉴权。
- SW生命周期缺陷已确定复现：本地短片播完，保持页面且强制stopAllWorkers后UI重播请求404、无meta/range、error4；手动重注册只恢复授权，已失败播放器仍因loaded标记不重开。主代理改为所有SW查询携带会话token，由当前页面再核验；保留已有worker Map拒绝错误token，Map空时可经当前client恢复查询。撤销携带自身token，旧房stop不清新房handler；错误媒体不再走已加载复用分支，手动再试能重open。安全边界、worker停启、Web10→2 seek、真实重播专项 `/tmp/eir-sw-idle-fixed-report.md` 待返回。
- 新房隔离复测通过：旧core Future未返回时，新房add B在121ms内完成并真实播放B；旧Future返回不覆新，owner长等待序号、会话清单与EOF回归通过。原精确竞态E2仍期待新房空列表的中间断言过期，已交测试方改为新代独立应用且保留最终真实Player断言，报告 `/tmp/eir-exact-race-refresh-report.md` 待返回。
- E2已按新代独立语义刷新并通过：旧gate未释放时重入快照A paused已落地，旧完成不回退，后续B实际播放0.42→1.37秒；E1不改仍通过，全量单元227项通过。报告 `/tmp/eir-exact-race-refresh-report.md`。
- SW取消标识改用标准`crypto.randomUUID()`，页面取消记录不再与重启后从1开始的worker计数冲突；JS桥接与Dart Web请求字段同步使用字符串。最终Web构建需同时包含main、bridge、SW三份匹配产物，并验证取消后重启再播放；该批更新后需刷新已打开的开发页面。
- 当前并行准备Android当前源码产品包与原生真实UI验收（保留数据安装、全ABI、明确模拟器证据）；报告 `/tmp/eir-android-current-native-report.md` 待返回。最终App/Web双向验收必须在Web生命周期专项通过后使用同批源码，不能复用旧Web构建。
- Web生命周期专项6项通过，含worker重启重播、token隔离、旧会话撤销、晚加入后向前seek及失败后重试，见 `/tmp/eir-sw-idle-fixed-report.md`。Android模拟器原生播放、主题设置与URL等通过，但末帧seek后播放曾卡住，见 `/tmp/eir-android-current-native-report.md`。主代理已让播放同时参考权威seek目标是否到达片尾；最新源码的末帧及App/Web双向联合验收 `/tmp/eir-final-complete-report.md` 仍在进行，未通过前不标记完成。
- 用户授权主代理直接接管测试后：最新源码Linux精确片尾seek及中段seek两项通过，时钟/分片13项通过；自行构建Web与Android并`install -r`保留首次安装时间。当前源码双浏览器真实测试通过暂停晚加入（5.72/5.62秒）、seek（2.1/2.1秒）、恢复推进及同邀请重入，结果`/tmp/eir-direct-dual-out/dual.json`。App/Web双向仍未证。
- 接管模拟器测试时，临时绑定现有ANGLE库后设备ADB停止响应且重连超时；已请用户恢复设备。必须先检查并撤销`/vendor/lib64/egl/*_emulation.so`上的三处临时绑定、恢复普通adbd及必要reverse，再继续双端测试，不能将其视作测试通过。
- 用户恢复设备后已确认临时绑定不存在，ADB与反向端口恢复，原有应用数据保留。实际定位 Web 拖动失败为 Flutter 默认 Service Worker 与媒体 Worker 争用同一作用域；自定义 bootstrap 并确认媒体 Worker 接管后，旧 Worker 迁移测试通过，模拟器 App 房主向 Brave 成员传输本地视频、播放及播放中拖动均真实通过。反方向及最终构建仍待验收。
- 退出或解散房间后播放器残留旧视频位置：已改为停止并清空播放器，Linux 真实播放器测试验证退出后位置、时长及列表清零，重新创建房间无旧内容。小窗口大厅及添加媒体弹窗遮挡问题已交 Agy 修复，修复后需重建和验证。
- 同一模拟器分屏反向实测：Brave 房主选本地 20 秒视频，Android 通过复制邀请加入，双方加载 20 秒并同步从 5 秒前进，暂停后约 15–16 秒，截图 `/tmp/eir-web-to-app-paused.png`。Android 画面因模拟器 EGL 黑屏，不能据此宣称图像渲染或真机通过；小窗口房间状态栏溢出及播放器操作遮挡继续交 Agy 修复。227 项 Flutter 测试、旧 Worker 迁移及 Linux 房间退出测试通过。
- 新 Web 构建通过双浏览器暂停晚加入、2.1 秒拖动、恢复推进及退出重入，已更新 8080 并核对 IPv4/IPv6 主脚本哈希。Android 保留数据安装后实测将 20 秒视频拖至 100% 再播放仍卡在 19 秒、显示播放中，不能视作片尾问题解决，正在采集精确播放器状态；Agy 房间 UI 修改期间的临时构建尚未通过。
- VM 现场读取到视频时长 20.023219 秒、末端目标 19.937 秒，间隔约 86 毫秒而旧容差仅 50 毫秒；现将近片尾容差设为 250 毫秒并在回零时重新打开媒体，Linux 真实播放器近片尾回归通过。Android 实测已回零但时间仍不推进，并出现 `EGL_BAD_ATTRIBUTE`；中途拖动时目标变化、实际时间仍停零，原因尚未排除，不能宣称 Android 片尾通过。新版房间 UI 的布局测试失败已交 Agy 修正，完成后重跑。
- Agy 修复房间布局后 UI 专项 15 项与全量 227 项通过。已按当前源码重新构建 Android debug 包并保留数据安装，首次安装时间不变，产物 `flutter-apk/eir-android-latest-debug.apk` SHA-256 为 `347e24092404ff1e9e90e4a20637fc03eae15f3dd8967b2c85c942ac8be1e982`；其模拟器片尾及真机画面仍未验收通过。新版 Web 的小窗口和双端回归仍在执行。
- Android 同一模拟器补充对照：新建房间播放 20 秒视频可到自然片尾，随后点击重播仍停在 0 秒，播放状态显示进行中；不能仅把故障归因于起播或做出 EGL 已证实为根因的结论。新版 Web 小窗口创建房间及本地文件选择按钮可见已验证；独立双浏览器重跑加入和播放仍在进行。
- Web 最新构建独立双浏览器重跑通过：暂停加入房主 6.07 秒、成员 5.81 秒，拖动双方 2.10 秒，成员恢复后 9.99→12.99 秒，同邀请重入成功；先前一次加入未成功未定位原因，不隐去该不稳定现象。8080 已更新至这批源码，IPv4/IPv6 主脚本和媒体 worker 哈希一致，小窗口本地文件选择按钮可见。
- 模拟器复现扩展：重播卡在 0 秒后切换到第二个本地视频，显示新视频及播放状态但仍停在 0 秒（`/tmp/eir-switch-baseline.png`）。故障覆盖播放器重新加载，不限片尾检测；日志有 EGL 失败，但尚未证明因果。不得标记 Android 整体验收完成。
- 临时启用 media_kit 详细日志确认：初次与再次加载时 GPU 输出均报 `Could not create EGL context`、`Failed initializing any suitable GPU context`、视频输出初始化失败，再次加载以错误 EOF 结束；这台模拟器无法可靠验证 Android 视频输出。诊断代码与含临时地址的日志已移除，并已将正式 debug 包覆盖安装回设备、保留用户数据。自然片尾重播仍需在可用图形环境复测，不能以此断言 Z Flip7 的表现。
- Web 最新构建另验证近片尾拖动后重播：视频从 2.74 秒推进到 5.81 秒，无媒体错误；8080 上旧 Flutter Worker 迁移至 Eir Worker 的测试通过。
- 用户表示已启用 OpenGL ES 后复测：模拟器仍使用 Intel Mesa 的 Android Emulator OpenGL ES Translator，系统运行时间约 9 小时 48 分钟；Eir 视频进度推进但画面仍黑，最新日志仍有 `eglCreateContext` / `EGL_BAD_ATTRIBUTE`。目前未验证所做配置在重启后是否生效，不能判定修复成功。
- 用户重启后（设备 uptime 约两分钟）重新实测本地视频：进度推进至 4 秒但画面仍黑，09:50:49 新日志两次出现 `eglCreateContext` / `EGL_BAD_ATTRIBUTE`；SurfaceFlinger 的 OpenGL ES 版本只能证明后端启动，不能证明视频输出已修复。ADB reverse 已恢复，Android 视频输出和重播验收继续未通过。
- 用户决定本轮跳过上述模拟器图形问题，作为验收豁免处理；不再以该问题阻塞当前进度。实际画面黑屏、EGL 报错和 Android 重播尚未得到有效验证的事实保留，豁免不表示故障修复或真机测试通过。
- 依用户要求，Android 应用 ID 改为 `com.norns.eir`；Norns 新建 Eir 项目并设为 developing。已使用独立正式密钥构建 1.0.0+1 APK，校验包名、签名和三种 ABI，并在模拟器安装启动；旧 `com.eir.app.eir` 保留，数据不自动迁移。构建与签名说明见 `ANDROID-RELEASE.md`。
- Web 普通 HTTP 域名下设置页空白：会话初始化失败时设置诊断无条件访问 `RoomSession.player` 并抛出 StateError；Agy 修正为显示播放器未就绪，保留其他设置功能。未初始化会话的展示与信令地址保存回归通过，相关 UI 测试 21 项通过；HTTP 域名桌面、手机实测可打开设置，手机实测信令地址写入本地存储。8080 已更新修复构建，IPv4/IPv6 脚本哈希一致；HTTP 下受安全上下文约束的房间能力仍不可据此认定可用。
