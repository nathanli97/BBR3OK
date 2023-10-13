#!/bin/bash

function check_root()
{
	[ "$(whoami)" == "root" ] || return 1
	return 0
}
function conditional_unset_ipv6_first()
{
	[ -f /root/.bbr3_onekey_install/set_ipv6_first ] && sed -i '/^label 2002\:\:\/16/d' /etc/gai.conf
}
function report_error()
{
	conditional_unset_ipv6_first
	echo $1
	exit 1
}

function set_sysctl()
{
	sed -i "s/[# ]?$1//g" /etc/sysctl.conf
}
function set_ipv6_first()
{
	echo "label 2002::/16   2" >> /etc/gai.conf
	touch /root/.bbr3_onekey_install/set_ipv6_first
	echo "由于检测到本机IPv4访问CF会触发验证，已自动转到IPv6优先模式"
}
echo "BBR3 一键安装脚本 by Nathanli1211(鸟临窗语报天晴)"
# This script only supports Ubuntu... other platforms not tested (yet)
check_root || report_error "请以root身份运行！"
# Install Xanmod from offical repo
mkdir /root/.bbr3_onekey_install >> /dev/null 2>&1
cd /root/.bbr3_onekey_install
echo 从官方源安装XANMOD 内核...

rm -f /usr/share/keyrings/xanmod-archive-keyring.gpg
[ -n "$(curl https://dl.xanmod.org/archive.key | grep 'Just a moment')" ] || set_ipv6_first
wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg || report_error "安装内核时出错"
echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list || report_error "安装内核时出错"
sudo apt update && sudo apt install -y linux-xanmod-x64v3 || report_error "安装内核时出错"
conditional_unset_ipv6_first
echo "优化系统配置..."


if grep -q "BBRv3-Xanmod" "/etc/sysctl.conf"; then
	echo "系统配置已经优化过；无需再次优化 -- 如果你需要重新优化，请先执行以下命令将系统配置文件恢复成未优化版本："
	echo "sudo cp /root/.bbr3_onekey_install/sysctl.conf /etc"
	exit
fi

echo "Original file is backup in /root/bbr3_onekey_install/sysctl.conf"
cp /etc/sysctl.conf /root/.bbr3_onekey_install/
# 以下配置来源于https://www.nodeseek.com/post-27396-1
cat >> /etc/sysctl.conf <<-EOF
# BBRv3-Xanmod
# 内核panic时，1秒后自动重启
kernel.panic = 1
# 允许更多的PIDs (减少滚动翻转问题); may break some programs 32768
kernel.pid_max = 32768
# 内核所允许的最大共享内存段的大小（bytes）
kernel.shmmax = 4294967296
# 在任何给定时刻，系统上可以使用的共享内存的总量（pages）
kernel.shmall = 1073741824
# 设定程序core时生成的文件名格式
kernel.core_pattern = core_%e
# 当发生oom时，自动转换为panic
vm.panic_on_oom = 1
# 表示强制Linux VM最低保留多少空闲内存（Kbytes）
# vm.min_free_kbytes = 1048576
# 该值高于100，则将导致内核倾向于回收directory和inode cache
vm.vfs_cache_pressure = 250
# 表示系统进行交换行为的程度，数值（0-100）越高，越可能发生磁盘交换
vm.swappiness = 10
# 仅用10%做为系统cache
vm.dirty_ratio = 10
vm.overcommit_memory = 1
# 增加系统文件描述符限制 2^20-1
fs.file-max = 1048575
# 网络层优化
## 虽然但是 xanmod 内核默认使用 fq
net.core.default_qdisc=fq
## xanmod 内核默认使用bbr3, 不必设置
# net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_ecn=1
# listen()的默认参数,挂起请求的最大数量，默认128
net.core.somaxconn = 1024
# 增加Linux自动调整TCP缓冲区限制
net.core.wmem_default = 16384
net.core.rmem_default = 262144
net.core.rmem_max = 536870912
net.core.wmem_max = 536870912
# 进入包的最大设备队列.默认是300
net.core.netdev_max_backlog = 2000
# 开启SYN洪水攻击保护
net.ipv4.tcp_syncookies = 1
# 开启并记录欺骗，源路由和重定向包
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
# 处理无源路由的包
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
# 开启反向路径过滤
# Aliyun 负载均衡实例后端的 ECS 需要设置为 0
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
# TTL
net.ipv4.ip_default_ttl = 64
# Cloudflare 生产环境对高吞吐量低延迟的优化配置
net.ipv4.tcp_rmem = 8192 262144 536870912
net.ipv4.tcp_wmem = 4096 16384 536870912
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_collapse_max_bytes = 6291456
net.ipv4.tcp_notsent_lowat = 131072
# Tcp自动窗口
net.ipv4.tcp_window_scaling = 1
# 进入SYN包的最大请求队列.默认1024
net.ipv4.tcp_max_syn_backlog = 8192
#让TIME_WAIT尽快回收 默认0
net.ipv4.tcp_tw_reuse = 1
#让TIME_WAIT状态可以重用，这样即使TIME_WAIT占满了所有端口，也不会拒绝新的请求造成障碍 默认是0
# 表示是否启用以一种比超时重发更精确的方法（请参阅 RFC 1323）来启用对 RTT 的计算；为了实现更好的性能应该启用这个选项
net.ipv4.tcp_timestamps = 0
# 表示本机向外发起TCP SYN连接超时重传的次数
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
# 减少处于FIN-WAIT-2连接状态的时间，使系统可以处理更多的连接。
net.ipv4.tcp_fin_timeout = 10
# 减少TCP KeepAlive连接侦测的时间，使系统可以处理更多的连接。
# 如果某个TCP连接在idle 300秒后,内核才发起probe.如果probe 2次(每次2秒)不成功,内核才彻底放弃,认为该连接已失效.
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 2
net.ipv4.tcp_keepalive_intvl = 2
# 系统所能处理不属于任何进程的TCP sockets最大数量
net.ipv4.tcp_max_orphans = 262144
# 系统同时保持TIME_WAIT套接字的最大数量，如果超过这个数字，TIME_WAIT套接字将立刻被清除并打印警告信息。
net.ipv4.tcp_max_tw_buckets = 20000
# arp_table的缓存限制优化
net.ipv4.neigh.default.gc_thresh1 = 128
net.ipv4.neigh.default.gc_thresh2 = 512
net.ipv4.neigh.default.gc_thresh3 = 4096
# 其他
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.netfilter.nf_conntrack_max = 1000000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries2 = 8
fs.inotify.max_user_instances = 8192
net.ipv4.route.gc_timeout = 100
# 阿里云优化
kernel.sysrq = 1
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2

EOF

sysctl -p

echo "完成。请手动执行reboot来重启服务器。"
