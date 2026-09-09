# On My Way 

学习过程的整理与记录：Python 基础、LeetCode HOT100、Agent、RAG、Prompt Engineering 与工程实践。单台阿里云 ECS 全栈自托管，零 CDN、零外链资源、零新增付费。

## 项目信息

| | |
|---|---|
| 线上站点 | <https://tuanzi-wow.cn> |
| GitHub | <https://github.com/chenghaoning51/OnMyWay> |
| Gitee | <https://gitee.com/tuanzi-wow/onmyway>（境内拉取源） |
| 技术栈 | Hugo 0.165.0（PaperMod）+ FastAPI（SQLite FTS5 + jieba）+ Nginx + systemd |
| 运行环境 | 单台阿里云 ECS（1.6 GiB / 固定 3 Mbps），Ubuntu，Git 为唯一内容源 |

## 架构

```
本地写笔记 ──git push──┬─> GitHub   公开副本，简历展示；国际链路抖动只影响它的新鲜度
                       └─> Gitee    境内拉取源，秒级稳定
                              │ blog-poll.timer 每 60s 轮询
                              ▼
                    deploy.sh：拉取 → hugo 构建 → 健全性检查 → 原子切软链 → nginx reload → 增量索引
                              │ 任一步失败不切版，线上保持旧内容
浏览器 ──HTTPS──> Nginx ──┬──> /        Hugo 静态产物（release 目录 + 软链原子切换）
                          ├──> /api/    FastAPI：SQLite FTS5 + jieba 全文检索、访问统计
                          └──> /_deploy webhook 接收器（HMAC 验签）

后台：blog-poll.timer   60s  拉取远端 → 触发发布（Webhook 备用）
      health.timer      5min 巡检 7 维（站点/磁盘/内存/证书/到期日/更新链路/备份新鲜度）→ 邮件告警
      backup.timer      每日 备份（bundle + 配置/证书 tar + DB → 本地滚动 14 天 + Gitee 私有仓库快照）
```

设计要点：

- **Git 即内容源**：笔记就是 Markdown，`git push` 即发布；GitHub 公开、Gitee 境内中转，服务器与 GitHub 解耦。
- **原子发布**：先建新 release 目录，构建 + 健全性检查通过才 `ln -sfn` + `mv -Tf` 原子切软链；失败不切版，线上「宁可旧，不可坏」。
- **静态优先**：nginx 直读静态文件，动态只有检索与统计一个 FastAPI 服务（绑 `127.0.0.1:8000`）。

## 构建与测试

本机（Windows，仓库根执行；Hugo extended ≥ 0.165.0，仓库 `tools/` 下有一份，该目录不入库）：

```powershell
tools\hugo\hugo.exe server -D          # 本地预览（含草稿）→ http://localhost:1313
tools\hugo\hugo.exe --gc --minify      # 全量构建，产物在 site/，判据 < 5 s
tools\hugo\hugo.exe --config tools/cfg-check.toml list all   # 无主题/无 git 校验（沙箱 dubious ownership 时用）
python tools/hook-selftest.py          # webhook 接收器 9 项断言，须 ALL-PASS
powershell -ExecutionPolicy Bypass -File scripts\preflight.ps1   # 本机只读预检，须全 PASS
powershell -File scripts\measure-latency.ps1 -BaseUrl https://tuanzi-wow.cn -Rounds 10   # SLA 实测
```

服务器（经 Workbench 整段粘贴幂等脚本；只读优先）：

```bash
bash scripts/deploy.sh --status        # 当前 release / 已发布 sha
bash scripts/deploy.sh --rollback      # 一条命令回滚（不重新构建）
python3 scripts/reindex.py --full      # 全量重建检索索引
curl -s http://127.0.0.1:8000/healthz  # 须含 posts 数
curl -s -o /dev/null -w '%{http_code}' https://tuanzi-wow.cn/healthz-nginx   # 期望 200
```

构建自检项：第三方资源标签 0、内部链接缺失 0、每篇恰好 1 个 H1、draft 未发布、sitemap/robots 生成。无 CI lint；检索/统计 API 与 nginx 只在服务器运行，本地预览只有静态页面。

## 目录结构

```
content/                  笔记 Markdown（分区目录 + _index.md 组织）
config.toml               Hugo 站点配置
layouts/  assets/  static/  模板、CSS、头像与站点图标
scripts/                  deploy.sh 发布 ｜ blogapi.py 检索统计 ｜ reindex.py 索引
                          health.py 巡检 ｜ blog-alert.py 告警 ｜ backup.sh 备份
                          deploy-hook.py webhook 接收器
deploy/                   服务器侧安装与配置模板（nginx / systemd / certbot / logrotate）
archetypes/               新笔记 front matter 模板
docs/                     plan.md 技术路线 ｜ runbook.md 运维手册 ｜ defects.md 缺陷记录
CHECKLIST.md              全部任务与状态位（进度台账）
AGENTS.md                 仓库协作约定
```

`docs/plan.md`、`docs/runbook.md` 含实例信息，本地留存不入库；`docs/defects.md` 入库。

## 相关文档

- [AGENTS.md](AGENTS.md) — 协作约定、命令与验收判据
- [CHECKLIST.md](CHECKLIST.md) — 任务台账与进度
- [docs/defects.md](docs/defects.md) — 已证实缺陷
