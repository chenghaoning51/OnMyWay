# On My Way · 境内自托管学习笔记博客

战个未来吧 · 学习过程的整理与记录：Python 基础、LeetCode HOT100、Agent、RAG、Prompt Engineering。

**线上**：https://tuanzi-wow.cn ｜ 一台 1.6 GiB 内存的阿里云 ECS，全栈自托管，新增付费 0 元。

## 架构

```
本地写笔记 ──git push──┬─> GitHub   （公开副本，简历展示；国际链路抖动只影响它的新鲜度）
                       └─> Gitee   （境内拉取源，秒级稳定）
                              │ blog-poll.timer 每 60s 轮询（Webhook 备案后接入）
                              ▼
                    deploy.sh：拉取 → hugo 构建 → 健全性检查 → 原子切版 → nginx reload → 增量索引
                              │ 任一步失败不切版，线上保持旧内容
浏览器 ──HTTPS──> Nginx ──┬──> /        Hugo 静态产物（release 目录 + 软链原子切换）
                          ├──> /api/    FastAPI：SQLite FTS5 + jieba 全文检索、访问统计
                          └──> /_deploy webhook 接收器（HMAC 验签）

后台：blog-backup.timer 每日备份（bundle + 配置/证书 tar + DB → 本地滚动 14 天 + Gitee 私有仓库快照）
      blog-health.timer 每 5 min 巡检 7 维（站点/磁盘/内存/证书/到期日/更新链路/备份新鲜度）→ QQ 邮件告警（单一出口）
```

## 实测数据

| 指标 | 实测值 | 判据 |
|---|---|---|
| 发布流程（git pull → hugo → 切版 → reindex） | **2 s** | — |
| push → 内容可见（备案期 IP 口径，60s 轮询周期主导） | **45 s**，目标 p95 < 60 s | ✅ |
| 发布 → 新内容可搜（增量索引） | **2 s** | < 5 s ✅ |
| 站内搜索延迟 p95（经 nginx，30 次） | **6.6 ms** | < 20 ms ✅ |
| 检索/统计服务常驻 RSS | **122 MiB** | ≤ 200 MiB ✅ |
| Hugo 全量构建 | 619 ms / 102 页 | < 5 s ✅ |
| Lighthouse（性能/无障碍/最佳实践/SEO） | 100 / 100 / 100 / 100 | ≥ 95 ✅ |
| 每日备份体积（bundle + tar + DB 快照） | ~0.9 MB × 滚动 14 天 | — |

## 内存预算

整站常驻 ≈ 320 MB / 1638 MB（19%）：系统 + sshd + nginx 基线 ~200 MB，检索/统计服务（FastAPI + uvicorn + jieba 词典）122 MB，巡检与备份按需瞬时。每个 systemd 服务都设 `MemoryMax`，`RuntimeMaxSec=86400` 每日自愈重启防内存漂移。swap 2 GiB + `swappiness=10` 兜底构建尖峰。

## 零付费下的取舍

- **不用 GitHub Pages/Vercel**：境内访问不稳，且检索与统计只能挂第三方；自托管才有「自有域名 + 自有数据」。
- **不用境外 CI Runner**：境外构建完推回境内要过同一 条不稳定的国际链路——改为**服务器本地 pull 式构建**，把不稳定面压缩到一次 git 拉取。
- **不用 WordPress/Halo**：内容进数据库就和「Git 是唯一内容源」冲突；Hugo 静态产物 + 原子切版才能做到「宁可旧，不可坏」。
- **不用 Docker**：1.6 GiB 上容器编排的常驻开销大于收益，systemd 单元 + 资源限制够用。
- **不用第三方统计/评论**：引用境外脚本拖慢页面且涉及隐私；`sendBeacon` + 自建 SQLite 统计 456 KB 就够。
- **Gitee 境内中转**：GitHub 的 https 对境内 ECS 间歇黑洞（SYN 丢弃 ~127 s）——服务器与 GitHub 解耦，poll/备份全走境内，国际链路抖动不再影响站点更新与告警。

## 故障路径（详见 runbook）

- **发布失败**：构建/健全性检查不过 → 不切版 + 告警邮件；回滚一条命令 `deploy.sh --rollback`。
- **内容误删**：内容源在 Git；检索库可由全量重建秒级恢复；每日备份双保险（本地 14 天滚动 + Gitee 快照）。
- **服务假死**：巡检 5 min 一轮 7 维探活，连续 2 次失败告警、恢复通知；`RuntimeMaxSec` 每日自愈重启。
- **证书/到期**：DNS-01 自动续期；巡检对证书 <30 天、域名/ECS 到期 <15 天提前告警。

## 目录

```
content/          笔记（Markdown，分区 _index.md 组织）
config.toml       站点配置
layouts/          自定义模板（搜索页、页脚埋点等）
deploy/           服务器侧：nginx 模板、systemd 单元、分阶段安装脚本
scripts/          deploy.sh（发布）、blogapi.py（检索统计）、reindex.py（索引）、
                  health.py（巡检）、blog-alert.py（告警）、backup.sh（备份）
```

`docs/plan.md` 与 `docs/runbook.md`（本地留存）记录完整技术路线、平台约束与运维手册。
