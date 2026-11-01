#!/usr/bin/env bash
# Проверка конфигурации учебного сервера
set -uo pipefail
PASS=0
FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL] %s (ожидалось: %s, получено: %s)\n' "$desc" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}
printf 'Аудит конфигурации: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
printf '[1] Служба SSH\n'
ssh_config=$(sudo sshd -T) || ssh_config=''
ssh_value() { awk -v key="$1" '$1 == key {print $2; exit}' <<< "$ssh_config"; }
check 'Вход от имени root запрещён' no "$(ssh_value permitrootlogin)"
check 'Парольная аутентификация отключена' no "$(ssh_value passwordauthentication)"
ssh_port=$(ssh_value port)
check 'SSH использует нестандартный порт' yes "$(if [[ "$ssh_port" =~ ^[0-9]+$ ]] && ((ssh_port > 0 && ssh_port < 65536 && ssh_port != 22)); then echo yes; else echo no; fi)"
check 'MaxAuthTries равен 3' 3 "$(ssh_value maxauthtries)"
printf '[2] Межсетевой экран\n'
ufw_status=$(sudo env LC_ALL=C ufw status verbose) || ufw_status=''
check 'Межсетевой экран активен' active "$(awk '/^Status:/{print $2}' <<< "$ufw_status")"
check 'Входящие соединения запрещены по умолчанию' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$ufw_status")"
printf '[3] Учётные записи\n'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
printf '[4] Веб-сервер\n'
check 'Nginx запущен' active "$(systemctl is-active nginx)"
check 'Настройка Nginx корректна' yes "$(if sudo nginx -t >/dev/null 2>&1; then echo yes; else echo no; fi)"
cert_days=${CERT_MIN_DAYS:-30}
check 'Сертификат действует достаточно долго' yes "$(if sudo openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$((cert_days * 86400))" >/dev/null 2>&1; then echo yes; else echo no; fi)"
check 'Права сайта и ключа корректны' yes "$(if [[ -z "$(find /var/www/devops-site -type f -perm -o+w -print)" ]] && [[ "$(sudo stat -c '%a' /etc/ssl/private/devops.key)" == 600 ]]; then echo yes; else echo no; fi)"
printf 'Пройдено: %s, не пройдено: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
