# actions-work-box

用 GitHub Actions 干活的盒子。

代码同步在 [shoguncao/actions-work-box](https://github.com/shoguncao/actions-work-box) 与 [mutedtowel/actions-work-box](https://github.com/mutedtowel/actions-work-box)。

- `shoguncao/actions-work-box`：代码备份，Actions 已关闭
- `mutedtowel/actions-work-box`：真正跑 Actions 的仓库

本地推送时，`origin` 指向 shoguncao，并同时 push 到 mutedtowel。

## 循环触发

`scripts/repeat-report-egress-ip.sh` 用来一次次启动 `report-egress-ip`：每次等出口 IP 写入记录页（或这次 Action 成功结束）后再启动下一次。接口请求带超时，避免一直卡住。

需要环境变量 `GH_TOKEN`（对 mutedtowel 仓库有 Actions 权限的 token）。不要把 token 写进仓库。

```bash
export GH_TOKEN=...
COUNT=2000 ./scripts/repeat-report-egress-ip.sh
```

记录页：https://xmrig_statistic.keyso.uk/actions-work-box/
