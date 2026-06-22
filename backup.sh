#!/bin/bash

# ============================================
# ЗАГРУЗКА ПЕРЕМЕННЫХ ИЗ .env
# ============================================
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Telegram
BOT_TOKEN="${TG_BOT_TOKEN:-}"
CHAT_ID="${TG_CHAT_ID:-}"
THREAD_ID="${TG_THREAD_ID_BACKUP:-}"

# ============================================
# КОНФИГУРАЦИЯ
# ============================================
BACKUP_DIR="${BACKUP_DIR:-/home/fellk/home-stack/backups}"
PASSPHRASE_FILE="/home/fellk/.backup_passphrase"
LOG_FILE="/home/fellk/home-stack/backup.log"
RCLONE_CONFIG="/home/fellk/.config/rclone/rclone.conf"
REMOTE_NAME="Yandex-Disk"
REMOTE_PATH="Backup/VPS_Германия"
TEST_DIR="/tmp/backup-test-$(date +%s)"
TEMP_BACKUP_DIR="/tmp/backup-$(date +%s)"

# ============================================
# ФУНКЦИИ
# ============================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

send_telegram() {
    local message="$1"
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
        local payload="chat_id=${CHAT_ID}&text=${message}&parse_mode=HTML"
        if [ -n "$THREAD_ID" ]; then
            payload="${payload}&message_thread_id=${THREAD_ID}"
        fi
        curl -s -X POST "$url" -d "$payload" > /dev/null 2>&1
    fi
}

# ============================================
# ФУНКЦИЯ ПОЛНОГО ТЕСТИРОВАНИЯ
# ============================================
test_backup() {
    local encrypted_file="$1"
    local test_dir="$2"
    
    log "🧪 ПОЛНОЕ ТЕСТИРОВАНИЕ БЭКАПА..."
    
    if [ ! -f "$encrypted_file" ]; then
        log "   ❌ Файл не найден: $encrypted_file"
        return 1
    fi
    log "   ✅ Файл существует"
    
    log "   🔍 Проверка GPG..."
    if ! gpg --batch --yes --passphrase-file "$PASSPHRASE_FILE" --decrypt "$encrypted_file" > /dev/null 2>&1; then
        log "   ❌ GPG ошибка"
        return 1
    fi
    log "   ✅ GPG OK"
    
    mkdir -p "$test_dir"
    log "   📁 Временная папка: $test_dir"
    
    log "   📦 Распаковка архива..."
    if ! gpg --batch --yes --passphrase-file "$PASSPHRASE_FILE" -d "$encrypted_file" | tar -xz -C "$test_dir" 2>/dev/null; then
        log "   ❌ Ошибка распаковки"
        rm -rf "$test_dir"
        return 1
    fi
    log "   ✅ Архив успешно распакован"
    
    log "   🔍 Проверка структуры..."
    local errors=0
    local checks=0
    
    critical_files=(
        "docker-compose.yml"
        "backup.sh"
        "check_stack.sh"
        "README.md"
        "LICENSE"
        ".env.example"
        ".gitignore"
        "monitoring/prometheus.yml"
        "monitoring/loki-config.yaml"
        "monitoring/mimir-config.yaml"
        "monitoring/alertmanager.yml.example"
        "reports/xui_clients_report.py"
    )
    
    log "   📋 Проверка критических файлов:"
    for file in "${critical_files[@]}"; do
        checks=$((checks + 1))
        if [ -f "$test_dir/$file" ]; then
            log "     ✅ $file"
        else
            log "     ❌ $file — ОТСУТСТВУЕТ!"
            errors=$((errors + 1))
        fi
    done
    
    # Проверка наличия БД
    if [ -f "$test_dir/backup-data/mongodb/mongodump.bson" ]; then
        log "   ✅ MongoDB дамп присутствует"
    else
        log "   ⚠️ MongoDB дамп отсутствует"
    fi
    
    if [ -f "$test_dir/backup-data/xui/x-ui.db" ]; then
        log "   ✅ XUI БД присутствует"
    else
        log "   ⚠️ XUI БД отсутствует"
    fi
    
    if [ -f "$test_dir/backup-data/npm/database.sqlite" ]; then
        log "   ✅ NPM БД присутствует"
    else
        log "   ⚠️ NPM БД отсутствует"
    fi
    
    local size=$(du -sh "$encrypted_file" | cut -f1)
    log "   📊 Размер бэкапа: $size"
    
    local file_count=$(find "$test_dir" -type f 2>/dev/null | wc -l)
    log "   📊 Количество файлов: $file_count"
    
    rm -rf "$test_dir"
    
    if [ $errors -eq 0 ]; then
        log "   ✅ ✅ ✅ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!"
        TEST_RESULT="✅ FULL OK (${checks} проверок, ${file_count} файлов)"
        return 0
    else
        log "   ❌ ❌ ❌ НАЙДЕНО $errors ОШИБОК!"
        TEST_RESULT="❌ Ошибок: $errors (${checks} проверок)"
        return 1
    fi
}

# ============================================
# 1. ДАМП БАЗ ДАННЫХ
# ============================================
dump_databases() {
    local dump_dir="$1"
    mkdir -p "$dump_dir"/{mongodb,xui,npm,monitoring-data}
    
    log "📀 Дамп баз данных..."
    
    # MongoDB дамп

    if docker ps | grep -q mtg-mongo; then
        log "   📁 Дамп MongoDB..."
        docker exec mtg-mongo mongodump --out /tmp/mongodump 2>/dev/null
        docker cp mtg-mongo:/tmp/mongodump "$dump_dir/mongodb/" 2>/dev/null
        docker exec mtg-mongo rm -rf /tmp/mongodump 2>/dev/null
        if [ -d "$dump_dir/mongodb/mongodump" ]; then
            log "   ✅ MongoDB дамп создан"
        fi
    else
        log "   ⚠️ MongoDB контейнер не найден"
    fi
    
    # XUI БД
    if [ -f "xui/db/x-ui.db" ]; then
        log "   📁 Копирование XUI БД..."
        cp xui/db/x-ui.db "$dump_dir/xui/"
        log "   ✅ XUI БД скопирована"
    fi
    
    # NPM БД
    if [ -f "npm/data/database.sqlite" ]; then
        log "   📁 Копирование NPM БД..."
        cp npm/data/database.sqlite "$dump_dir/npm/"
        log "   ✅ NPM БД скопирована"
    fi
    
    # Данные мониторинга (только последние 7 дней)
    log "   📁 Копирование данных мониторинга (за 7 дней)..."
    
    # Prometheus data (только метаданные, не все чанки)
    if [ -d "monitoring/prometheus-data" ]; then
        mkdir -p "$dump_dir/monitoring-data/prometheus"
        find monitoring/prometheus-data -name "*.wal" -o -name "*.tmp" -mtime -7 | \
            tar -cf - -T - 2>/dev/null | tar -xf - -C "$dump_dir/monitoring-data/prometheus/" 2>/dev/null || true
        log "   ✅ Prometheus данные скопированы"
    fi
    
    # Loki data (только индексы)
    if [ -d "monitoring/loki-data" ]; then
        mkdir -p "$dump_dir/monitoring-data/loki"
        tar -czf "$dump_dir/monitoring-data/loki/index.tar.gz" \
            monitoring/loki-data/index/ 2>/dev/null || true
        log "   ✅ Loki индексы скопированы"
    fi
}

# ============================================
# 2. БЭКАП ЛОГОВ (только за 7 дней)
# ============================================
backup_logs() {
    local dest_dir="$1"
    mkdir -p "$dest_dir/logs"
    
    log "📄 Бэкап логов (последние 7 дней)..."
    
    # Docker контейнеры логи
    for container in $(docker ps --format '{{.Names}}'); do
        docker logs --since 7d "$container" > "$dest_dir/logs/${container}.log" 2>&1 2>/dev/null || true
    done
    
    # Системные логи
    journalctl --since "7 days ago" > "$dest_dir/logs/system.log" 2>/dev/null || true
    
    log "   ✅ Логи сохранены"
}

# ============================================
# 3. ОСНОВНОЙ БЭКАП
# ============================================
log "=========================================="
log "🚀 Запуск процесса резервного копирования"
log "📁 Локальная директория бэкапов: $BACKUP_DIR"

mkdir -p "$BACKUP_DIR"

# Создаем временную папку для сбора данных
TEMP_DIR="/tmp/backup-stack-$(date +%s)"
mkdir -p "$TEMP_DIR"

# Копируем конфиги и скрипты
log "📦 Копирование конфигурационных файлов..."
cp -r \
    backup.sh \
    check_stack.sh \
    docker-compose.yml \
    README.md \
    LICENSE \
    .env.example \
    .gitignore \
    .gitmodules \
    monitoring/ \
    reports/ \
    xui-api-exporter-repo/ \
    "$TEMP_DIR/" 2>/dev/null || true

# Копируем конфиги NPM
if [ -d "npm/data/nginx" ]; then
    mkdir -p "$TEMP_DIR/npm/data/nginx"
    cp -r npm/data/nginx/* "$TEMP_DIR/npm/data/nginx/" 2>/dev/null || true
    log "   ✅ Конфиги NPM скопированы"
fi

# Копируем конфиги LetsEncrypt
if [ -d "npm/letsencrypt/renewal" ]; then
    mkdir -p "$TEMP_DIR/npm/letsencrypt/renewal"
    cp -r npm/letsencrypt/renewal/* "$TEMP_DIR/npm/letsencrypt/renewal/" 2>/dev/null || true
    log "   ✅ Конфиги LetsEncrypt скопированы"
fi

# Копируем сертификаты XUI
if [ -d "xui/cert" ]; then
    mkdir -p "$TEMP_DIR/xui/cert"
    cp -r xui/cert/* "$TEMP_DIR/xui/cert/" 2>/dev/null || true
    log "   ✅ Сертификаты XUI скопированы"
fi

# Копируем данные MTG (MongoDB данные)
if [ -d "mtg/mongo-data" ]; then
    mkdir -p "$TEMP_DIR/mtg"
    cp -r mtg/mongo-data "$TEMP_DIR/mtg/" 2>/dev/null || true
    log "   ✅ Данные MTG скопированы"
fi

# Создаем дампы БД
dump_databases "$TEMP_DIR/backup-data"

# Создаем бэкап логов
backup_logs "$TEMP_DIR"

# ============================================
# СОЗДАНИЕ АРХИВА
# ============================================
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/secure-stack_${TIMESTAMP}.tar.gz"
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"

log "📦 Создание архива ($TEMP_DIR)..."
cd "$TEMP_DIR"
tar -czf "$BACKUP_FILE" . 2>/dev/null
cd - > /dev/null

if [ $? -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✅ Архив создан (размер: $SIZE)"
else
    log "❌ Ошибка создания архива"
    send_telegram "❌ <b>Ошибка бэкапа!</b>%0AНе удалось создать архив"
    exit 1
fi

# Очистка временной папки
rm -rf "$TEMP_DIR"

# ============================================
# ШИФРОВАНИЕ
# ============================================
log "🔒 Шифрование архива..."

if [ ! -f "$PASSPHRASE_FILE" ]; then
    log "❌ Файл с паролем не найден: $PASSPHRASE_FILE"
    send_telegram "❌ <b>Ошибка бэкапа!</b>%0AФайл с паролем не найден"
    exit 1
fi

gpg --batch --yes --passphrase-file "$PASSPHRASE_FILE" -c "$BACKUP_FILE"

if [ $? -eq 0 ] && [ -f "$ENCRYPTED_FILE" ]; then
    SIZE=$(du -h "$ENCRYPTED_FILE" | cut -f1)
    log "✅ Бэкап создан успешно!"
    log "   Имя: $(basename "$ENCRYPTED_FILE")"
    log "   Размер: $SIZE"
    rm -f "$BACKUP_FILE"
else
    log "❌ Ошибка шифрования"
    send_telegram "❌ <b>Ошибка бэкапа!</b>%0AНе удалось зашифровать архив"
    exit 1
fi

# ============================================
# ЗАГРУЗКА НА ЯНДЕКС.ДИСК
# ============================================
if command -v rclone &> /dev/null && [ -f "$RCLONE_CONFIG" ]; then
    log "☁️  Загрузка файла на Яндекс.Диск..."
    rclone --config "$RCLONE_CONFIG" mkdir "${REMOTE_NAME}:${REMOTE_PATH}" 2>/dev/null || true
    rclone --config "$RCLONE_CONFIG" copy "$ENCRYPTED_FILE" "${REMOTE_NAME}:${REMOTE_PATH}/" --progress
    
    if [ $? -eq 0 ]; then
        log "✅ Файл успешно загружен на Яндекс.Диск"
        UPLOAD_STATUS="✅ Загружен"
    else
        log "❌ Ошибка загрузки на Яндекс.Диск"
        UPLOAD_STATUS="❌ Ошибка"
    fi
else
    log "⚠️ rclone не настроен, пропускаем загрузку"
    UPLOAD_STATUS="⏭️ Пропущено"
fi

# ============================================
# ПОЛНОЕ ТЕСТИРОВАНИЕ БЭКАПА
# ============================================
TEST_DIR="/tmp/backup-test-$(date +%s)"
test_backup "$ENCRYPTED_FILE" "$TEST_DIR"
TEST_EXIT_CODE=$?

# ============================================
# УДАЛЕНИЕ СТАРЫХ БЭКАПОВ
# ============================================
log "🗑️ Удаление бэкапов старше 30 дней..."
find "$BACKUP_DIR" -name "*.gpg" -type f -mtime +30 -delete 2>/dev/null

# ============================================
# СТАТИСТИКА
# ============================================
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.gpg" -type f 2>/dev/null | wc -l)
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

log "📊 Итоговая статистика:"
log "   - Локальных бэкапов: $BACKUP_COUNT, размер: $BACKUP_SIZE"
log "   - Загрузка: $UPLOAD_STATUS"
log "   - Тест: $TEST_RESULT"

# ============================================
# УВЕДОМЛЕНИЕ
# ============================================
SIZE=$(du -h "$ENCRYPTED_FILE" | cut -f1)
MESSAGE="✅ <b>Резервное копирование завершено!</b>%0A%0A"
MESSAGE="${MESSAGE}📁 <b>Файл:</b> $(basename "$ENCRYPTED_FILE")%0A"
MESSAGE="${MESSAGE}📦 <b>Размер:</b> $SIZE%0A"
MESSAGE="${MESSAGE}📊 <b>Локальных бэкапов:</b> $BACKUP_COUNT%0A"
MESSAGE="${MESSAGE}💾 <b>Общий размер:</b> $BACKUP_SIZE%0A"
MESSAGE="${MESSAGE}☁️ <b>Яндекс.Диск:</b> $UPLOAD_STATUS%0A"
MESSAGE="${MESSAGE}🧪 <b>Тест:</b> $TEST_RESULT%0A"
MESSAGE="${MESSAGE}📅 <b>Дата:</b> $(date '+%Y-%m-%d %H:%M:%S')"

send_telegram "$MESSAGE"

if [ $TEST_EXIT_CODE -eq 0 ]; then
    log "✅ Резервное копирование завершено успешно!"
else
    log "⚠️ Резервное копирование завершено, но тесты показали ошибки!"
fi
log "=========================================="
