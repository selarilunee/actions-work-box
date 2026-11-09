# actions-work-box

用 GitHub Actions 干活的盒子。

代码同步在 [shoguncao/actions-work-box](https://github.com/shoguncao/actions-work-box) 与 [mutedtowel/actions-work-box](https://github.com/mutedtowel/actions-work-box)。

- `shoguncao/actions-work-box`：代码备份，Actions 已关闭。不要在这边跑循环。
- `mutedtowel/actions-work-box`：真正跑 Actions 的仓库，循环也要对着这边触发。

本地推送时，`origin` 指向 shoguncao，并同时 push 到 mutedtowel。

## 循环触发

`scripts/repeat-report-egress-ip.sh` 用来一次次启动 `report-egress-ip`：每次等我们自己的记录页出现新记录后再启动下一次，不靠 GitHub 运行列表来判断结束。接口请求带短超时，后台启动后超过 15 秒仍未结束就强制结束该请求；强杀后既不再等待它退出，也不在外层用会等待后台任务的方式去接结果，避免仍卡住几分钟。

需要环境变量 `GH_TOKEN`（对 mutedtowel 仓库有 Actions 权限的 token）。不要把 token 写进仓库。

```bash
export GH_TOKEN=...
COUNT=2000 ./scripts/repeat-report-egress-ip.sh
```

国内直连 GitHub 有时会不通（尤其晚上）。不用改脚本，启动前给 curl 加上代理环境变量即可。2019 机器上 Articles 代理已经在跑，可用：

```bash
export ALL_PROXY=socks5h://127.0.0.1:18080
# 或者：export HTTPS_PROXY=http://127.0.0.1:9174
export GH_TOKEN=...
COUNT=5000 ./scripts/repeat-report-egress-ip.sh
```

记录页：https://xmrig_statistic.keyso.uk/actions-work-box/

## 手动临时 SSH

`.github/workflows/cloudflare-ssh.yml` 只能手动运行，直接 `uses` [action-sshd-cloudflared](https://github.com/valeriangalliat/action-sshd-cloudflared) v4。不代替 `report-egress-ip`，也不挡住它。shoguncao 的 Actions 是关的，要在能跑 Actions 的仓库上点 Run workflow。

日志是组件自己的原文，比较长。在它打印的 `ssh -o ProxyCommand=...` 那一行里，`ssh` 后面加上 `-i /path/to/action-sshd-cloudflared`（私钥，不是 `.pub`），主机名和 `known_hosts` 那一段保持原样。临时断开：Ctrl-b 然后 d。结束会话：`tmux kill-session -t debug`。最长 360 分钟。

没有实际跑过这条 workflow，也没有做过 SSH 连通测试。

