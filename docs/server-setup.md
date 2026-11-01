# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

Ubuntu Server 24.04.5 LTS ARM64 без графической оболочки; Parallels Desktop на Mac ARM64. 2 vCPU, 2048 МБ памяти, динамический диск 25 ГБ. Исходный официальный cloud image проверен по SHA256. Установка через cloud-init вместо установщика VirtualBox; это различие среды выполнения.

## 2. Сетевые интерфейсы

- `nat0`: Shared/NAT, MAC `00:1c:42:15:fe:09`, DHCP `10.211.55.5/24`, шлюз `10.211.55.1`.
- `lab0`: Host-only, MAC `00:1c:42:28:92:0b`, статический `10.37.129.101/24`. Адрес Mac в этом сегменте — `10.37.129.2`.
- На Mac в `/etc/hosts`: `10.37.129.101 devops.local`.

В текущей сети исходящий DNS гостевой машины не отвечает, хотя SSH по Host-only работает. Для установки пакетов использован временный обратный SOCKS-туннель через SSH. Он не публикует порт в локальную сеть: на сервере слушает только `127.0.0.1:1080`. Настройки VPN на Mac не менялись. При необходимости повторить установку:

```bash
# Mac, оставить соединение открытым на время установки пакетов
ssh -N -R 127.0.0.1:1080 devops
# VM: временная настройка APT
printf 'Acquire::http::Proxy "socks5h://127.0.0.1:1080";\nAcquire::https::Proxy "socks5h://127.0.0.1:1080";\n' | sudo tee /etc/apt/apt.conf.d/80-bootstrap-proxy
sudo apt update
# После установки удалить только временный конфигурационный файл
sudo rm /etc/apt/apt.conf.d/80-bootstrap-proxy
```

## 3. Подключение с хоста

В этом стенде SSH доступен напрямую по Host-only, проброс NAT `127.0.0.1:2222` не используется. До усиления защиты порт VM — 22, после — 2222. В `~/.ssh/config` на Mac:

```sshconfig
Host devops
    HostName 10.37.129.101
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
    ControlMaster auto
    ControlPersist 600
    ControlPath ~/.ssh/devops-%r-%p
```

Отпечаток Ed25519 сервера сверялся с консолью VM: `SHA256:ISLOLXJRzkLlNvP8Orrm6mNvUWOrYV4oIAt58nHFtbc`. После отката на исходный снимок временно использовать `student`, порт 22. Сверять ключ перед добавлением в `known_hosts`.

## 4. Учётные записи

`student` (UID 1000) — исходный пользователь с sudo. `devops` (UID 1001) входит в группы `devops`, `sudo`. После усиления SSH разрешён только `devops`, только по ключу. Отдельная пара Ed25519 находится на Mac в `~/.ssh/devops_vm`; закрытый ключ не доставляется на сервер и не входит в репозиторий. На VM: `/home/devops/.ssh` — 700, `authorized_keys` — 600, владелец `devops:devops`.

Чтобы восстановить учётную запись после отката: `sudo adduser devops`, `sudo usermod -aG sudo devops`, затем `ssh-copy-id -i ~/.ssh/devops_vm.pub devops@10.37.129.101`. Сначала проверить новый вход по ключу, затем усиливать SSH.

## 5. Служба SSH

Основной файл сохранён в `/etc/ssh/sshd_config.backup`. Дополняющий файл `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментирована конфликтующая строка `PasswordAuthentication yes`: для большинства директив SSH действует первое найденное значение. Перед применением выполнить `sudo sshd -t`, проверить `sudo sshd -T`. Отключить активацию сокетом: `sudo systemctl disable --now ssh.socket`; включить службу `sudo systemctl enable --now ssh.service`; применить `sudo systemctl restart ssh`. Не закрывать старое соединение до проверки нового на порту 2222. Отказы root и подключения без ключа подтверждаются в `sudo journalctl -u ssh`.

Полное имя сервера: `devops-vm.devops.local`; в `/etc/hosts` VM строка `127.0.1.1 devops-vm.devops.local devops-vm`.

## 6. Правила межсетевого экрана

До включения UFW разрешить управляющий порт:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment HTTP
sudo ufw allow 443/tcp comment HTTPS
sudo ufw enable
sudo ufw logging medium
sudo ufw status verbose
```

Правила действуют для IPv4 и IPv6. Порт 8080 закрыт: обращение с Mac по IP заканчивается тайм-аутом, запись `UFW BLOCK` содержит `SRC=10.37.129.2`, `DST=10.37.129.101`, `PROTO=TCP`, `DPT=8080`. Не открывать шесть новых SSH-соединений за 30 секунд; использовать постоянное соединение.

`scripts/audit.sh` запускать на VM. На штатной конфигурации: 6 проверок OK, код 0. При временном `MaxAuthTries 10`: 5 OK, 1 FAIL, код 1. Затем вернуть 3 и проверить `sshd -t` и аудит повторно.

## 7. Снимки состояния

- `01-clean-install`: обновлённый Ubuntu Server, пользователь student, две сети, SSH до изменения защиты.
- `02-keys-configured`: создан devops и проверен вход по отдельному ключу.
- `03-ssh-hardened`: проверены порт 2222, запрет root и парольного входа; до настройки UFW.

Снимки созданы 1 ноября 2026 года. После отката соответствующим образом выбирать SSH-порт и учётную запись. Конфигурация UFW и записи hosts воспроизводятся по разделам выше.
