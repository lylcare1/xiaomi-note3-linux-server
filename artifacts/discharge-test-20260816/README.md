# 放电测试数据 — 2026-08-16

设备: Xiaomi Mi Note 3 (jason, SDM660), 内核 6.19.10-sdm660 r35
条件: USB 拔除, 仅 WiFi (LYL, IP 10.255.181.209), ath10k power_save off, 11 timer 监控运行中

## 文件说明

| 文件 | 内容 | 采样频率 |
|---|---|---|
| discharge.log | cap/电压/电流/估算功率/负载/温度 (放电主数据) | 2min |
| power.log | USB 输入侧功耗 (拔线前) | 1h |
| battery-care.log | 电池健康快照 | 1h |
| journal-monitors.log | temp/net/health/disk-io 监控 (journald 导出) | 5-10min |

## 关键时间线 (CST)

- 21:50:17 首条记录 (USB 仍连接, stat=Full)
- 21:57:03 USB 拔除, 转 Discharging (v=4313mV, i=-191mA, 823mW)
- 22:03:49 v=4274mV, 瞬时 1440mW (timer 任务叠加)

## 放电速率 (截至 22:03)

- 稳态功耗: 0.76-0.82W (WiFi 常开 + 监控), 峰值 1.44W
- 电压斜率: 满电平台期 ~39mV / 6.8min
- 续航预估: 99%→20% ≈ 13h (avg 0.8W, 电池 13.3Wh)
- 预计自动软关机 (cap≤20% 或 v≤3500mV): 次日上午 ~11:00

## 低电保护

discharge-monitor.sh: cap≤20% 或 v≤3500mV → safe-poweroff.sh 自动 halt
(2026-08-16 22:06 修正日志单位 uA→mA 后重新部署)

## 注意

- discharge.log 持续累积在设备 /var/log/monitor-logs/, 本目录为快照存档
- 测试结束后拉取完整日志覆盖此快照, 并补充最终放电曲线结论
