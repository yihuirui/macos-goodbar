# Changelog

User-visible changes for each release are listed here.

## 0.3.6 (build 9) — adaptive menu-bar width, quota split, Apple-grid icon

- Menu-bar summary width now adapts to the display: on narrow screens (below 1600 pt logical width) the summary switches to a compact layout, mid-size displays use a standard width, and wide displays keep the previous full layout. A new "菜单栏宽度" setting (设置 → 显示项目) lets you pin 紧凑 / 标准 / 完整 per machine, overriding the automatic choice; the change takes effect immediately.
- The combined quota item ("7 天额度") is split into two independent items: "5h 额度" (five-hour window, keeps the `gpt.usage` key) and a new "7d 额度" (`gpt.usage7d`). Each can be toggled for the Touch Bar and the menu-bar summary separately, and each shows only its own window. Existing configurations are migrated once: `gpt.usage7d` is inserted right after `gpt.usage` so the visible content stays the same until you untick one of them.
- The Dock icon now follows the Apple macOS icon grid: an 824×824 continuous-corner squircle centred on a 1024×1024 canvas with transparent margins, instead of the previous full-bleed rounded square, so it matches neighbouring icons in size and corner shape.
- The app is renamed to "GoodBar": the bundle folder, display name, installer zip and user-facing copy now say GoodBar. The bundle identifier (`io.github.yihuirui.goodtouchbar`) and internal type names are unchanged, so settings and the fan helper keep working across the rename.

## 0.3.5 (build 8) — Codex status icon and reset clock

- Restore the original full-color Codex status icon when quota is selected; keep the black thumbs-up Dock icon unchanged.
- Show the five-hour quota's absolute local reset time, with tomorrow/date labels across calendar days. Unknown and expired times remain explicit, and stale data stays marked.
- Preserve 12 pt white status text and at least three selected summary items; widen the measured ceiling modestly for the longer time label.
- Bundle verification checks the copied Codex PNG byte-for-byte against the original resource.

## 0.3.4 (build 7) — experimental preview

- Render the status summary as a full-color image inside the native status button so menu-bar vibrancy cannot recolor the fixed white 12 pt text.
- Preserve the compact two-window Codex quota, readable three-item layout, accessibility value, and native left/right status actions.
- Verify real `NSStatusBarButton` raster output across Aqua, Dark Aqua, Vibrant Light and Vibrant Dark appearances on gray backgrounds.

## 0.3.3 (build 6) — experimental preview

- Render status values in fixed white 12 pt text and allow a roomy item width so at least three selected values remain readable.
- Give the selected Codex quota a compact five-hour and weekly percentage summary; keep reset details, stale state, and unavailable state available.
- Preserve quota visibility when it appears later in the saved selection order, while retaining relative order for other selected items and bounding long custom values with ellipses.

## 0.3.2 (build 5) — experimental preview

- Restore the original black thumbs-up bundle and Dock icon, and make menu-only launches available from the Dock.
- Show checkbox-selected menu values beside the status icon in saved order, cap the item width, and keep an icon-only state when no menu values are selected.
- Keep left-click status details and right-click full-menu actions, with display settings reachable from the Dock-opened window and app menu.

## 0.3.1 (build 4) — experimental preview

- Refine the native status details hierarchy using Hallmark and Impeccable design guidance: quieter grouping, clearer quota and token information, and more distinct WorkBuddy actions.
- Preserve existing data sources, refresh cadence, action confirmations, and hardware capability checks.
- Keep design-tool downloads outside the published source and application packages; no new runtime dependency is required.

## 0.3.0 (build 3) — experimental preview

- Replace the primary status-item text menu with a native details popover: separate five-hour and weekly quota cards, today's token usage, AI state, and a compact system overview.
- Keep the complete action menu accessible with a right click and the details panel's More entry; group diagnostics separately from everyday actions.
- Use existing monitoring snapshots for presentation; opening the panel does not start WorkBuddy retry or install a fan helper.
- Retain menu-only and Touch Bar modes, Apple silicon read-only fan policy, and separate native packages.

## 0.2.0 (build 2) — experimental preview

Released as an [experimental preview](https://github.com/yihuirui/GoodBar/releases/tag/v0.2.0), with native Apple silicon support alongside Intel.

- Add Auto, On, and Off Touch Bar modes with model allowlist detection and conservative menu-only behavior for unsupported or unknown models.
- Add Apple silicon CPU, memory, thermal-zone, AI activity, and menu-only support; keep fan readings read-only and omit the fan helper from arm64 packages.
- Add separate Touch Bar and menu layouts in `goodtouchbar-layout` schema v2 while retaining schema v1 import compatibility.
- Prepare separate native `x86_64` and `arm64` packages and CI jobs.

Automated checks do not establish physical Touch Bar presentation, player response, Apple silicon sensor coverage, or fan-write validation. See [README.md](README.md) for current release boundaries.

## 0.1.0 (build 1) — release preparation

This source package is being prepared for its first public release. No release artifact has been published.

- Prepare AI and System layout presets with the `goodtouchbar-layout` schema v1.
- Add a native system-controls panel for output volume, mute, play/pause, and app switching.
- Keep AI quota, optional token usage and output-speed estimates, WorkBuddy status/retry, system metrics, and experimental Intel fan control in clearly separated feature areas.
- Begin preparing an Intel `x86_64` macOS 13+ build and public contribution/security documentation.

This entry describes the 0.1.0 release target; automated checks do not establish real Touch Bar, OS-compatibility, or fan-write validation. See [README.md](README.md) for current release boundaries.
