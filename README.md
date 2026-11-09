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

`.github/workflows/cloudflare-ssh.yml` 是另一条 workflow，只能在 Actions 页面手动运行（Run workflow）。没有 push，也没有定时。它不代替 `report-egress-ip`，也不会挡住那条上报或循环脚本；两条各跑各的，互不影响。

真正开跑要在 [mutedtowel/actions-work-box](https://github.com/mutedtowel/actions-work-box/actions/workflows/cloudflare-ssh.yml)。shoguncao 那边 Actions 是关的，不要在那边点。

跑的是 GitHub 托管的临时 Ubuntu runner，用 [action-sshd-cloudflared](https://github.com/valeriangalliat/action-sshd-cloudflared) v4 开一个随机的 Cloudflare quick tunnel。组件会把当次连接命令打在运行日志里，不上传到 ix.io 或其他粘贴板，也不使用仓库 secrets。v4 不能改写它打印的 SSH 命令，所以 workflow 第一步用中文说明要复制哪一行、私钥加在哪。

本机要先装好 [`cloudflared`](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/)，并且终端里能直接运行 `cloudflared`。私钥文件是 `action-sshd-cloudflared`，不是 `action-sshd-cloudflared.pub`。

在运行日志里找到 `Run the following command to connect:` 下面那一整行（以 `ssh-keygen -R action-sshd-cloudflared` 开头）。整行复制，只在最后的 `ssh` 和 `-o` 之间加上 `-i /path/to/action-sshd-cloudflared`。`https://....trycloudflare.com` 用日志里的实际主机名。前面的 `ssh-keygen -R` 和写入 `known_hosts` 的 `echo` 要留下，那是在校验这次的主机公钥。组件若另外给出 `UserKnownHostsFile=/dev/null` 和 `StrictHostKeyChecking=accept-new` 的替代命令，那是不校验主机公钥的写法；要校验就用带 `known_hosts` 的那一整行。

登录后会进入 tmux 会话 `debug`。

- 临时断开、稍后还能连回：先按 Ctrl-b，松开，再按 d。runner、隧道和 tmux 会话都还在，用同一条命令（同一主机名，仍带 `-i`）重连。这不是 `exit`。
- 结束会话并让 workflow 收尾：在 tmux 里的 shell 执行 `exit`。这是最后一个 shell 时，会话结束，组件会关掉隧道和 SSH。如果还开了别的窗口，执行 `tmux kill-session -t debug`。`exit` 不是临时登出，结束后不能再连。
- 如果这样 job 还在跑：在 Actions 里对这次运行点 Cancel workflow，无条件终止。

job 最长 360 分钟。runner 是临时的，job 一结束机器就销毁，隧道地址也不能再用。

这里只说明用法。仓库里没有实际触发过这条 workflow，也没有做过 SSH 连通测试。

