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
    
    # 1. Проверка существования файла
    if [ ! -f "$encrypted_file" ]; then
        log "   ❌ Файл не найден: $encrypted_file"
        return 1
    fi
    log "   ✅ Файл существует"
    
    # 2. Проверка GPG
    log "   🔍 Проверка GPG..."
    if ! gpg --batch --yes --passphrase-file "$PASSPHRASE_FILE" --decrypt "$encrypted_file" > /dev/null 2>&1; then
        log "   ❌ GPG ошибка — файл поврежден или неверный пароль"
        return 1
    fi
    log "   ✅ GPG OK — файл может быть расшифрован"
    
    # 3. Создаем временную папку для восстановления
    mkdir -p "$test_dir"
    log "   📁 Временная папка: $test_dir"
    
    # 4. Распаковка архива
    log "   📦 Распаковка архива..."
    if ! gpg --batch --yes --passphrase-file "$PASSPHRASE_FILE" -d "$encrypted_file" | tar -xz -C "$test_dir" 2>/dev/null; then
        log "   ❌ Ошибка распаковки архива"
        rm -rf "$test_dir"
        return 1
    fi
    log "   ✅ Архив успешно распакован"
    
    # 5. Проверка структуры
    log "   🔍 Проверка структуры..."
    
    local errors=0
    local checks=0
    
    # Список критических файлов, которые должны быть в бэкапе
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
    
    # 6. Проверка YAML синтаксиса
    log "   🔍 Проверка YAML файлов..."
    local yaml_errors=0
    for yaml_file in $(find "$test_dir" -name "*.yml" -o -name "*.yaml" 2>/dev/null); do
        if command -v yq &> /dev/null; then
            if ! yq eval 'true' "$yaml_file" > /dev/null 2>&1; then
                log "     ❌ Ошибка YAML: $(basename "$yaml_file")"
                yaml_errors=$((yaml_errors + 1))
            fi
        else
            # Если yq нет, проверяем с помощью python
            if command -v python3 &> /dev/null; then
                if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                    log "     ❌ Ошибка YAML: $(basename "$yaml_file")"
                    yaml_errors=$((yaml_errors + 1))
                fi
            fi
        fi
    done
    
    if [ $yaml_errors -eq 0 ] && [ -n "$(find "$test_dir" -name "*.yml" 2>/dev/null)" ]; then
        log "   ✅ Все YAML файлы валидны"
    fi
    
    # 7. Проверка Docker Compose
    if [ -f "$test_dir/docker-compose.yml" ]; then
        log "   🔍 Проверка docker-compose.yml..."
        if command -v docker-compose &> /dev/null; then
            if docker-compose -f "$test_dir/docker-compose.yml" config > /dev/null 2>&1; then
                log "   ✅ docker-compose.yml валиден"
            else
                log "   ❌ docker-compose.yml содержит ошибки"
                errors=$((errors + 1))
            fi
        fi
    fi
    
    # 8. Проверка размера
    local size=$(du -sh "$encrypted_file" | cut -f1)
    log "   📊 Размер бэкапа: $size"
    
    # 9. Количество файлов
    local file_count=$(find "$test_dir" -type f 2>/dev/null | wc -l)
    log "   📊 Количество файлов: $file_count"
    
    # 10. Очистка
    log "   🧹 Очистка временной папки..."
    rm -rf "$test_dir"
    
    # Итог
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
# ОСНОВНАЯ ЛОГИКА
# ============================================
log "=========================================="
log "🚀 Запуск процесса резервного копирования"
log "📁 Локальная директория бэкапов: $BACKUP_DIR"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/secure-stack_${TIMESTAMP}.tar.gz"
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"

# ============================================
# СОЗДАНИЕ АРХИВА
# ============================================
log "📦 Создание архива..."

# 1. Конфиги и скрипты
tar -czf "$BACKUP_FILE" \
    backup.sh \
    check_stack.sh \
    docker-compose.yml \
    README.md \
    LICENSE \
    .env.example \
    .gitignore \
    .gitmodules \
    monitoring/*.yml \
    monitoring/*.yaml \
    monitoring/*.example \
    reports/ \
    xui-api-exporter-repo/ \
    2>/dev/null || true

# 2. Конфиги NPM (без сертификатов)
if [ -d "npm/data/nginx" ]; then
    log "   📁 Добавляем конфиги NPM..."
    tar -rf "$BACKUP_FILE" \
        npm/data/nginx/proxy_host/*.conf \
        npm/data/nginx/redirection_host/*.conf \
        npm/data/nginx/default_host/*.conf \
        npm/data/nginx/stream/*.conf \
        npm/data/nginx/dead_host/*.conf \
        npm/data/nginx/temp/*.conf \
        2>/dev/null || true
fi

# 3. База данных NPM
if [ -f "npm/data/database.sqlite" ]; then
    log "   📁 Добавляем базу данных NPM..."
    tar -rf "$BACKUP_FILE" \
        npm/data/database.sqlite \
        2>/dev/null || true
fi

# 4. Конфиги LetsEncrypt (без сертификатов)
if [ -d "npm/letsencrypt/renewal" ]; then
    log "   📁 Добавляем конфиги LetsEncrypt..."
    tar -rf "$BACKUP_FILE" \
        npm/letsencrypt/renewal/*.conf \
        2>/dev/null || true
fi

# 5. База данных XUI
if [ -f "xui/db/x-ui.db" ]; then
    log "   📁 Добавляем базу данных XUI..."
    tar -rf "$BACKUP_FILE" \
        xui/db/x-ui.db \
        2>/dev/null || true
fi

if [ $? -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✅ Архив создан (размер: $SIZE)"
else
    log "❌ Ошибка создания архива"
    send_telegram "❌ <b>Ошибка бэкапа!</b>%0AНе удалось создать архив"
    exit 1
fi

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
log "📨 Отправка уведомления в Telegram (топик $THREAD_ID)..."

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
