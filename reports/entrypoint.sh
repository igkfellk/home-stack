#!/bin/sh
# Сохраняем текущие переменные окружения в /etc/environment
printenv > /etc/environment

# Запускаем cron в фоне
cron -f -L /var/log/cron.log &

# Ждём, чтобы контейнер не завершался
tail -f /var/log/cron.log
