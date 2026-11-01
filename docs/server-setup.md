# Настройка сервера

## 1. Виртуальная машина

- Ubuntu Server 24.04 ARM64, без рабочего стола.
- Parallels: 2 ядра, 2 ГБ ОЗУ, диск 25 ГБ.
- Пользователь при установке: `student`.

## 2. Сеть

- NAT: `nat0`, адрес `10.211.55.5`, шлюз `10.211.55.1`.
- Host-only: `lab0`, адрес сервера `10.37.129.101`, адрес Mac `10.37.129.2`.
- На Mac в `/etc/hosts` добавлено: `10.37.129.101 devops.local`.

Прямой доступ VM к пакетам сейчас не работает. Для установки использован SSH-туннель:

```bash
# На Mac, оставить открытым на время установки
ssh -N -R 127.0.0.1:1080 devops
# На VM
sudo apt -o Acquire::http::Proxy=socks5h://127.0.0.1:1080 update
```

Порты и адреса отличаются от примера VirtualBox: работа выполнена в Parallels на Mac.

## 3. Подключение

До настройки: `ssh -i ~/.ssh/devops_vm student@10.37.129.101` (порт 22).
После настройки: `ssh devops` (порт 2222).
Проброс портов NAT не нужен: подключаемся по Host-only.

На Mac в `~/.ssh/config`:

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

Ключ сервера проверен по консоли. Отпечаток Ed25519: `SHA256:ISLOLXJRzkLlNvP8Orrm6mNvUWOrYV4oIAt58nHFtbc`.

## 4. Пользователи и ключи

```bash
# На VM под student
sudo adduser devops
sudo usermod -aG sudo devops
# На Mac
ssh-keygen -t ed25519 -f ~/.ssh/devops_vm -C devops-vm-key
ssh-copy-id -i ~/.ssh/devops_vm.pub devops@10.37.129.101
```

Новый ключ создавать только при его отсутствии. Закрытый ключ остаётся на Mac.
На VM каталог `/home/devops/.ssh` имеет права 700, файл `authorized_keys` — 600. Владелец — devops.

## 5. Защита SSH

Сохранить копию: `sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup`.
В `/etc/ssh/sshd_config.d/99-hardening.conf`:

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

В `50-cloud-init.conf` закомментировать `PasswordAuthentication yes`, иначе настройка выше не сработает.

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo sshd -T
sudo ss -tlnp | grep sshd
```

Старое соединение не закрывать, пока не проверен новый вход на порту 2222.
Имя сервера — `devops-vm`. В `/etc/hosts` VM: `127.0.1.1 devops-vm.devops.local devops-vm`.

## 6. Межсетевой экран и проверка

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw logging medium
sudo ufw status verbose
```

Сначала разрешить SSH, затем включать UFW. Частые новые SSH-соединения могут блокироваться.
Запрос с Mac к `10.37.129.101:8080` блокируется. Запись в `/var/log/ufw.log`: источник `10.37.129.2`, получатель `10.37.129.101`, TCP, порт 8080.

На VM запустить `scripts/audit.sh`: исправная настройка даёт код 0. Для проверки временно поставить `MaxAuthTries 10`: код должен стать 1. Затем вернуть 3 и снова проверить.

## 7. Снимки

- `01-clean-install` — чистая обновлённая система.
- `02-keys-configured` — вход devops по ключу.
- `03-ssh-hardened` — SSH на порту 2222, root и парольный вход запрещены.

Созданы 01.11.2026. При откате учитывать порт и пользователя из раздела 3.

## 8. Веб-сервер

- Установлен пакет `nginx`. Служба запускается автоматически.
- Файл настройки: `/etc/nginx/sites-available/devops-site`; копия в `config/nginx-devops-site.conf`.
- Ссылка включения: `/etc/nginx/sites-enabled/devops-site`. Стандартный сайт отключён.
- Сайт: `/var/www/devops-site`, владелец devops, каталоги 755, файлы 644.
- Сертификат: `/etc/ssl/certs/devops.crt`, права 644. Ключ: `/etc/ssl/private/devops.key`, root, права 600.

```bash
sudo apt install nginx
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj /CN=devops.local -addext subjectAltName=DNS:devops.local
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo cp config/nginx-devops-site.conf /etc/nginx/sites-available/devops-site
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

На Mac скопировать сертификат: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`.
Проверка: `curl --cacert ~/devops.crt https://devops.local/`.
Доставка: `scripts/deploy.sh --dry-run`, затем `scripts/deploy.sh` из чистого репозитория.
В macOS rsync использует символьную запись прав; результат тот же: каталоги 755, файлы 644.
