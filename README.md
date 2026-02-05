# hy2

一个用于 **Hysteria2** 的一键管理脚本。  
支持自签证书（域名固定 `bing.com`）、随机五位端口、随机密码，并提供 `hy2` 快捷菜单管理。

---

## 功能特性

- 一键安装 Hysteria2
- 自签证书（CN=`bing.com`）
- 随机五位端口（10000-65535）
- 随机密码
- 输出客户端连接信息（URI）
- 快捷命令 `hy2`（菜单式管理）
- 支持操作：
  - 安装
  - 查看信息
  - 查看状态
  - 重启
  - 换端口
  - 换密码
  - 卸载

---

## 系统要求

- Linux 服务器（Debian / Ubuntu / CentOS / Rocky / AlmaLinux 等）
- `root` 权限
- 可访问外网（用于下载安装 Hysteria2）

---

## 一键执行

可直接使用以下命令一键下载并运行脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/obace/hy2/main/hy2.sh -o hy2.sh && chmod +x hy2.sh && bash hy2.sh

