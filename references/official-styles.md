# 官方 Web 客户端 CSS 体系完整规格

> 来源：`assets/official/index-BMndL2ru.css`（2026-09-08 完整抓取，384KB）。
> 这是官方 Tailwind v4 编译产物——**所有样式真身都在这里**，比 JS bundle 里的
> 原子类组合更可靠。改样式前先查此文件，勿凭 JS 猜。
> 深色/浅色成对出现（值两套）。

## 1. 主题变量（语义色）

`:root{--ui-font-size:14px}` —— 基础字号 14px，全局唯一非主题变量。

### 背景/表面

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-background` | `#161616` (neutral-900) | `#f8f8f8` (neutral-50) |
| `--color-background-alt` | `color-mix(background 70%, transparent)` / `#26262699` | `color-mix(neutral-100 60%, transparent)` / `#fafafab3` |
| `--color-background-win-alt` | `#2b2b2b` (neutral-800) | `#ececee` (neutral-200) |
| `--color-card` | `#2b2b2b` (neutral-800) | `#fff` (white) |
| `--color-card-border` | = `--color-border` | 同左 |
| `--color-card-selected` | `#404040` (neutral-700) | `#e5e5e5` (neutral-200) |

### 边框/悬停

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-border` | `#ffffff1a`（白10%） | `#0d0d0d1a`（黑10%） |
| `--color-border-hover` | `#ffffff26`（白15%）| `#0d0d0d26`（黑15%） |
| `--color-brand` | `#fff` | `#000` |

### 正文层级（foreground 系列）

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-foreground` | `#dedede`（实测） | `#3a3a3a`（实测） |
| `--color-foreground-subtle` | 白 60% 级 | 黑 60% 级 |
| `--color-foreground-subtlest` | 更浅（已停用行用） | 更浅 |
| `--color-foreground-inverse` | `#000`（diff 前景用） | `#fff` |

### 状态色

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-success` | `#46bf72` (green-500) | `#1e8a3e` (green-600) |
| `--color-warning` | `#f59e0b` (amber-500) | 同左 |
| `--color-destructive` | red-500 `#ff5c5c` | red-600 `#e03131` |
| `--color-accent` | `#052f4a80`（sky-950 50%） | `#ebf4ff`（sky-50） |

### diff 色（文件变更）

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-diff-added` | `#46bf72` (green-500) | `#1e8a3e` (green-600) |
| `--color-diff-added-foreground` | `#fff` | `#000` |
| `--color-diff-removed` | `#ff5c5c` (red-500) | `#e03131` (red-600) |
| `--color-diff-removed-foreground` | `#fff` | `#000` |

### 文件节点（files mention 数据源配色）

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-file-node` | `#0084cc24` / sky-400 18% | `#1a70b81a` / sky-600 14% |
| `--color-file-node-hover` | `#00bcfe3d` / sky-400 24% | `#1a70b829` / sky-600 24% |
| `--color-file-node-foreground` | `#8fc5ef` (sky-300) | `#1a70b8` (sky-600) |

### 命令节点（/ 命令菜单）

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-command-node` | `#9aa6b424` (slate-300 16%) | `#5662701a` (slate-600 16%) |
| `--color-command-node-hover` | `#cad5e238` (slate-300 22%) | `#56627029` (slate-600 22%) |
| `--color-command-node-foreground` | `#b5c0cc` (slate-300) | `#566270` (slate-600) |

### 查找高亮（页面内搜索）

| 变量 | 深色 | 浅色 |
|---|---|---|
| `--color-find-highlight` | `#713f12` / `#fde68a` | `#542500` / `#fff4eb` |
| `--color-find-highlight-active` | `#facc15` / `#ffb26b` | `#a16207` / `#ff8a30` |

### 上下文用量环形圈色板（7 档，从深到浅）

| 档位 | 深色 | 浅色 |
|---|---|---|
| breakdown-1 | `#4099ff` (sky-400) | `#0b7fff` (sky-600) |
| breakdown-2 | `#66adff` (sky-300) | `#338fff` (sky-500) |
| breakdown-3 | `#80beff` (sky-200) | `#5ca7ff` (sky-400) |
| breakdown-4 | `#9dceff` / sky-200 84%+white | `#85bbff` / `#c3eafe` |
| breakdown-5 | `#b9ddff` / sky-200 72%+white | `#acd0ff` / `#ccedfe` |
| breakdown-6 | `#d0e8ff` / sky-200 60%+white | `#c8ddff` / `#d4f0ff` |
| breakdown-7 | `#e0ecff` / sky-200 48%+white | `#ddf3ff` / `#e4f1ff` |

> 实现：浅色 4-7 档 = `color-mix(sky-200 X%, white)`，即 sky 往白走。

## 2. 轨迹色（消息时间线）

| 角色 | 基色 | /80 变体（深色） |
|---|---|---|
| assistant | teal-700 `#0f766e` | `#0f766ecc` |
| reasoning | violet-700 `#7c3aed` | `#7c3aedcc` |
| tool-call | amber-600 `#d97706` | `#d97706cc` |
| tool-result | sky-600 `#0284c7` | `#0284c7cc` |
| user | blue-600 `#2563eb` | `#2563ebcc` |

类：`.text-trajectory-{role}`、`.text-trajectory-{role}\/80`（80% 透明度）。

## 3. radius / 字号

- radius 表：`xs=2px, sm=4px, md=6px, lg=8px, xl=12px, 2xl=16px`（ZRadius 已落地）
- `--ui-font-size:14px`；`text-ui-base` = 14px，`text-ui-sm` = 更小
- spacing 单位：Tailwind `--spacing` = 4px（`calc(var(--spacing) * N)`）

## 4. @keyframes 全集（36 个）

### 已落地/已知
- `gradient-flow`（流光正文）：`0% 100%→50% 0→to 0`，4s linear infinite
- `cua-group-gradient-flow`（CUA 组渐变）：`100% 0 → -100% 0`
- `markdown-image-loading-shimmer`：`100% 0 → -100% 0`

### 新发现（之前文档完全没有）

| 动画名 | 定义 | 用途推断 |
|---|---|---|
| `zcode-stream-text-in` | `0% opacity:0 → to opacity:1` | 流式文本淡入 |
| `zcode-stream-marker-in` | `0% color:#0000 → to var(--color-foreground-subtlest)` | 流式光标/标记 |
| `zcode-reaction-pop` | `0% scale(0)→45% 1.3→70% .95→to 1` | 点赞点踩弹出 |
| `zcode-reaction-particles` | box-shadow 6 点扩散（`7.7px 2.1px`→`15.5px 4.1px`），20% 时 opacity .7 | 点赞粒子 |
| `zcode-draft-prompt-waterfall` | `0% opacity 0, clip-path inset(0 0 100%), translateY(-12px)` | 草稿提示瀑布 |
| `zcode-update-charge-sweep` | `translate(-120%)→(260%)`, opacity .35→.9→.35 | 用量充值扫光 |
| `zcode-task-interaction-countdown` | `scaleX(var(--zcode-interaction-progress,1))→0` | 交互确认倒计时条 |
| `zcode-alarm-ring` | `rotate(-10deg)→10deg` | 铃铛告警 |
| `zcode-claim-ticket-enter` | `translateZ(-900px) rotateX(0) scale(.24) → translateZ(0) rotateX(720deg) scale(1)` | 工单 3D 入场 |
| `zcode-claim-ticket-enter-front/back` | 三段 visibility 交替（24.6%/42.6%/57.3%/75.4%） | 工单双面翻转 |
| `zcode-claim-ticket-native-back` | visibility hidden | 工单背面 |
| `zcode-claim-galaxy-drift` | `translate(-50%,-50%) rotate(-12deg) scale(.96) → rotate(-7deg) scale(1.05)` | 工单星系漂移 |
| `zcode-claim-star-warp` | `opacity 0→.12→.58→0, translate(10px) scaleX(.08) → translate(340px) scaleX(2.5)` | 星际穿越粒子 |
| `zcode-collapsible-up` | `height: var(--radix-collapsible-content-height) → 0` | 折叠收回 |
| `zcode-collapsible-fade-out` | `opacity 1→0` | 折叠淡出 |
| `workspace-remote-connecting-breathe` | brand 10%→16% bg + inset ring，50% 峰值 | 远程连接呼吸 |
| `browser-use-operation-breathe` | `opacity .5 scale(.9) → 1/1.08` 50% 峰值 | CUA 操作中呼吸 |
| `task-search-result-highlight` | brand 20%→14%→0 bg + ring | 任务搜索高亮 |
| `fork-highlight-pulse` | brand 24% bg + ring 脉冲一次 | 分叉高亮 |
| `accordion-down/up` | height 0 ↔ var(--radix-accordion-content-height) | 手风琴 |
| `collapsible-down/up` | 同 collapsible，多 provider 变量回退 | 折叠展开/收回 |
| `enter/exit` | Tailwind 变体驱动（--tw-enter-* 变量） | 通用进出场 |
| `ping/pulse/spin` | Tailwind 标准 | 通用 |

## 5. 容器查询（@container 完整断点）

### composer（named container）
| 断点 | 触发内容 |
|---|---|
| `not (width>=480px)` | `@max-[480px]/composer:inline-flex`（隐藏+切换布局） |
| `not (width>=24rem)` | icon-only：size-7/justify-center/gap-0/p-0 |
| `>=24rem` (384px) | `@sm/composer:block/hidden/inline-flex` |
| `>=32rem` (512px) | `@lg/composer:hidden` |
| `>=36rem` (576px) | `@xl/composer`：block/hidden + h-7/w-fit/justify-between/gap-1/pr-1.5/pl-2（chip 完整形态） |
| `>=42rem` (672px) | `@2xl/composer:inline` |

### conversation（named container）
| 断点 | 触发内容 |
|---|---|
| `not (width>=360px)` | `@max-[360px]/conversation:hidden` |
| `>=28rem` (448px) | `@md/conversation:px-6` |
| `>=624px` | `max-w-xl`（正文限宽） |
| `>=864px` | `visible/w-[calc(100%-6rem)]/max-w-4xl/translate-x-0`（侧栏出现） |
| `>=1280px` | `right-4/left-auto/flex/max-h-[min(64dvh,32rem)]`（状态面板悬浮位） |

### topoverlayer（用量 popover 容器）
| 断点 | 触发内容 |
|---|---|
| `>=216px` | `relative/hidden/w-auto/opacity-100` |
| `>=280px` | 同上（两档内容密度） |

### 其他
- `repo-wiki not (width>=560px)`：h-auto/max-h-72/w-full/flex-col/border-r-0
- `repo-wiki >=760px`：inline-flex
- `side-pane-open-tab >=480px`：grid 9rem 列/5.5rem 行
- `workspace-header not (width>=420px)`：hidden + max-w-[22vw]
- `workspace-header not (width>=560px)`：size-8/w-7/w-auto/max-w-32/branch 图标隐藏

## 6. 状态类

- `.is-assistant` / `.is-user`：group 状态类，子元素用 `:is(:where(.group).is-assistant *)` 变体
- `.text-trajectory-*`：轨迹色文字

## 7. 原文存档

完整 CSS 在 `assets/official/index-BMndL2ru.css`（384KB，minified 2 行）。
抓取日期 2026-09-08，对应官方 /remote/v4 线上版。
