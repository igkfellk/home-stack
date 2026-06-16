#!/bin/bash

# --- Настройки ---
BACKUP_DIR="${BACKUP_DIR:-/home/fellk/home-stack/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_BACKUP_FILE="/tmp/secure-stack_$TIMESTAMP.tar.gz"
FINAL_BACKUP_FILE="$BACKUP_DIR/secure-stack_$TIMESTAMP.tar.gz.gpg"
PASSPHRASE_FILE="/home/fellk/.backup_passphrase"
LOG_FILE="/home/fellk/home-stack/backup.log"
TEST_DIR="/tmp/backup_test_$TIMESTAMP"

# --- Яндекс.Диск настройки (rclone) ---
RCLONE_REMOTE="Yandex-Disk"
RCLONE_PATH="Backup/VPS_Германия"
RCLONE_CONFIG="/home/fellk/.config/rclone/rclone.conf"  # ВАЖНО: путь к конфигу

# --- Telegram настройки ---
BOT_TOKEN="${TG_BOT_TOKEN}"
CHAT_ID="${TG_CHAT_ID}"
THREAD_ID="${TG_THREAD_ID_BACKUP}"

# --- Функция логирования ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- Функция отправки в Telegram ---
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        -d "message_thread_id=$THREAD_ID" \
        -d "text=$message" \
        -d "parse_mode=HTML" > /dev/null 2>&1
}

# --- Функция тестирования бэкапа ---
test_backup() {
    local backup_file="$1"
    local test_result="✅"
    
    log "🧪 Начинаем тестирование бэкапа: $(basename "$backup_file")"
    
    # 1. Проверяем, что файл существует и не пустой
    if [ ! -f "$backup_file" ] || [ ! -s "$backup_file" ]; then
        log "❌ Файл бэкапа не существует или пуст"
        echo "❌" > /tmp/backup_test_result
        echo "Файл не существует или пуст" > /tmp/backup_test_messages
        return 1
    fi
    log "   ✅ Файл существует и не пуст"
    
    # 2. Проверяем целостность GPG-файла
    log "   Проверка GPG-подписи/целостности..."
    if gpg --batch --passphrase-file "$PASSPHRASE_FILE" --decrypt "$backup_file" > /dev/null 2>&1; then
        log "   ✅ GPG-файл целостен и может быть расшифрован"
    else
        log "   ❌ ОШИБКА: Не удалось расшифровать файл GPG"
        echo "❌" > /tmp/backup_test_result
        echo "Ошибка расшифровки GPG" > /tmp/backup_test_messages
        return 1
    fi
    
    # 3. Создаем временную директорию для тестовой распаковки
    mkdir -p "$TEST_DIR"
    
    # 4. Расшифровываем и проверяем архив
    log "   Распаковка архива для проверки структуры..."
    if gpg --batch --passphrase-file "$PASSPHRASE_FILE" --decrypt "$backup_file" 2>/dev/null | tar -tzf - > /dev/null 2>&1; then
        log "   ✅ Архив успешно прочитан (список файлов получен)"
    else
        log "   ❌ ОШИБКА: Не удалось прочитать содержимое архива"
        echo "❌" > /tmp/backup_test_result
        echo "Ошибка чтения архива" > /tmp/backup_test_messages
        rm -rf "$TEST_DIR"
        return 1
    fi
    
    # 5. Проверка структуры backup
    log "   Проверка структуры backup (чтение списка файлов)..."
    
    FILE_LIST=$(gpg --batch --passphrase-file "$PASSPHRASE_FILE" --decrypt "$backup_file" 2>/dev/null | tar -tzf - 2>/dev/null)
    
    if [ -n "$FILE_LIST" ]; then
        # Проверяем наличие критических файлов
        if echo "$FILE_LIST" | grep -q "docker-compose.yml"; then
            log "   ✅ Найден docker-compose.yml"
        else
            log "   ⚠️ В архиве не найден docker-compose.yml (возможно, это нормально)"
        fi
        
        if echo "$FILE_LIST" | grep -q "monitoring/prometheus.yml"; then
            log "   ✅ Найден prometheus.yml"
        else
            log "   ⚠️ В архиве не найден prometheus.yml"
        fi
        
        FILE_COUNT=$(echo "$FILE_LIST" | wc -l)
        log "   📊 Всего файлов в архиве: $FILE_COUNT"
        
        if [ $FILE_COUNT -lt 20 ]; then
            log "   ⚠️ В архиве очень мало файлов ($FILE_COUNT). Возможно, архив поврежден."
        fi
    else
        log "   ❌ Не удалось получить список файлов архива"
        echo "❌" > /tmp/backup_test_result
        echo "Не удалось получить список файлов" > /tmp/backup_test_messages
        rm -rf "$TEST_DIR"
        return 1
    fi
    
    # 6. Очистка
    rm -rf "$TEST_DIR"
    log "   🧹 Временная директория удалена"
    
    # 7. Итоговый результат
    log "✅ Тестирование бэкапа прошло успешно!"
    echo "✅" > /tmp/backup_test_result
    echo "Все проверки пройдены" > /tmp/backup_test_messages
    return 0
}

# --- Начало скрипта ---
log "=========================================="
log "🚀 Запуск процесса резервного копирования"

# 1. Создаём директорию для бэкапов
mkdir -p "$BACKUP_DIR"
log "📁 Локальная директория бэкапов: $BACKUP_DIR"

# 2. Проверяем/создаём файл с паролем
if [ ! -f "$PASSPHRASE_FILE" ]; then
    log "🔑 Создаём новый файл с паролем: $PASSPHRASE_FILE"
    openssl rand -base64 32 > "$PASSPHRASE_FILE"
    chmod 600 "$PASSPHRASE_FILE"
fi

# 3. Проверка прав root
if [[ $EUID -ne 0 ]]; then
    log "❌ ОШИБКА: Скрипт должен быть запущен от root"
    log "   Используйте: sudo $0"
    send_telegram "❌ <b>ОШИБКА бэкапа</b>%0AСкрипт должен быть запущен от root"
    exit 1
fi

# 4. Создание архива
log "📦 Создание и шифрование архива..."

cd /home/fellk/home-stack || {
    log "❌ ОШИБКА: Не удалось перейти в директорию /home/fellk/home-stack"
    send_telegram "❌ <b>ОШИБКА бэкапа</b>%0AНе удалось перейти в директорию home-stack"
    exit 1
}

# Создаём архив с исключениями
tar -cpzf "$TEMP_BACKUP_FILE" \
    --exclude='./backups' \
    --exclude='./monitoring/prometheus-data' \
    --exclude='./monitoring/loki-data' \
    --exclude='./monitoring/mimir-data' \
    --exclude='./xui-api-exporter-repo' \
    --exclude='./.git' \
    --exclude='*.log' \
    --exclude='./node_modules' \
    --exclude='./backup.sh' \
    . 2>/dev/null

TAR_EXIT_CODE=$?

if [ $TAR_EXIT_CODE -eq 0 ] || [ $TAR_EXIT_CODE -eq 1 ]; then
    log "✅ Архив tar создан (код: $TAR_EXIT_CODE)"
else
    log "❌ Фатальная ошибка при создании архива (код: $TAR_EXIT_CODE)"
    send_telegram "❌ <b>ОШИБКА бэкапа</b>%0AФатальная ошибка при создании архива (код: $TAR_EXIT_CODE)"
    exit 1
fi

# Шифруем архив
log "🔒 Шифрование архива..."
gpg --symmetric --batch --passphrase-file "$PASSPHRASE_FILE" -o "$FINAL_BACKUP_FILE" "$TEMP_BACKUP_FILE"

if [ $? -eq 0 ]; then
    FILE_SIZE=$(du -h "$FINAL_BACKUP_FILE" | cut -f1)
    log "✅ Бэкап создан успешно!"
    log "   Имя: $(basename "$FINAL_BACKUP_FILE")"
    log "   Размер: $FILE_SIZE"
else
    log "❌ ОШИБКА: Не удалось зашифровать архив"
    send_telegram "❌ <b>ОШИБКА бэкапа</b>%0AНе удалось зашифровать архив"
    rm -f "$TEMP_BACKUP_FILE"
    exit 1
fi

# Удаляем временный файл
rm -f "$TEMP_BACKUP_FILE"
log "🧹 Временный файл удалён"

# 5. Загрузка на Яндекс.Диск с помощью rclone
log "☁️  Загрузка файла на Яндекс.Диск ($RCLONE_REMOTE:$RCLONE_PATH)..."

if ! command -v rclone &> /dev/null; then
    log "❌ ОШИБКА: Утилита 'rclone' не установлена"
    send_telegram "❌ <b>ОШИБКА бэкапа</b>%0AУтилита rclone не установлена.%0AУстановите: sudo apt install rclone"
    exit 1
fi

# Проверяем, что файл существует
if [ ! -f "$FINAL_BACKUP_FILE" ]; then
    log "❌ ОШИБКА: Файл бэкапа не найден: $FINAL_BACKUP_FILE"
    UPLOAD_STATUS="❌ Ошибка: файл не найден"
else
    # Создаем папку на Яндекс.Диске, если её нет
    log "   Создание папки на Яндекс.Диске (если не существует)..."
    rclone --config "$RCLONE_CONFIG" mkdir "$RCLONE_REMOTE:$RCLONE_PATH" 2>> "$LOG_FILE"
    
    # Копируем файл на Яндекс.Диск
    log "   Загрузка файла (размер: $FILE_SIZE)..."
    
    # Загружаем и сохраняем вывод
    RCLONE_OUTPUT=$(rclone --config "$RCLONE_CONFIG" copy --verbose "$FINAL_BACKUP_FILE" "$RCLONE_REMOTE:$RCLONE_PATH" 2>&1)
    RCLONE_EXIT_CODE=$?
    
    # Записываем вывод в лог (для отладки)
    if [ -n "$RCLONE_OUTPUT" ]; then
        echo "$RCLONE_OUTPUT" >> "$LOG_FILE"
    fi
    
    if [ $RCLONE_EXIT_CODE -eq 0 ]; then
        log "✅ Файл успешно загружен на Яндекс.Диск в папку /$RCLONE_PATH"
        UPLOAD_STATUS="✅ Загружен на Яндекс.Диск"
    else
        log "❌ ОШИБКА: Не удалось загрузить файл на Яндекс.Диск (код: $RCLONE_EXIT_CODE)"
        log "   Подробности ошибки в логе выше"
        UPLOAD_STATUS="❌ Ошибка загрузки (код: $RCLONE_EXIT_CODE)"
    fi
fi

# 6. Тестирование созданного бэкапа
test_backup "$FINAL_BACKUP_FILE"
TEST_RESULT=$(cat /tmp/backup_test_result 2>/dev/null || echo "❌")
TEST_MESSAGES=$(cat /tmp/backup_test_messages 2>/dev/null || echo "Ошибка тестирования")

# 7. Удаление старых бэкапов (локально)
log "🗑️  Удаление локальных бэкапов старше $RETENTION_DAYS дней..."

DELETED_COUNT=0
OLD_BACKUPS=$(find "$BACKUP_DIR" -name "secure-stack_*.tar.gz.gpg" -type f -mtime +$RETENTION_DAYS)

if [ -n "$OLD_BACKUPS" ]; then
    DELETED_COUNT=$(echo "$OLD_BACKUPS" | wc -l)
    log "   Найдено старых бэкапов: $DELETED_COUNT"
    
    echo "$OLD_BACKUPS" | while read -r file; do
        rm -f "$file"
        log "   Удалён: $(basename "$file")"
    done
    log "✅ Удалено $DELETED_COUNT старых локальных бэкапов"
else
    log "ℹ️  Старых локальных бэкапов для удаления не найдено"
fi

# 8. Статистика
TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "secure-stack_*.tar.gz.gpg" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

log "📊 Итоговая статистика:"
log "   - Локальных бэкапов: $TOTAL_BACKUPS, общий размер: $TOTAL_SIZE"
log "   - Загрузка на Яндекс.Диск: $UPLOAD_STATUS"
log "   - Результат тестирования: $TEST_RESULT"

# 9. Отправка уведомления в Telegram
log "📨 Отправка уведомления в Telegram (топик $THREAD_ID)..."

MESSAGE="✅ <b>Резервное копирование завершено</b>%0A%0A"
MESSAGE+="📦 <b>Файл:</b> secure-stack_$TIMESTAMP.tar.gz.gpg%0A"
MESSAGE+="📊 <b>Размер:</b> $FILE_SIZE%0A"
MESSAGE+="☁️ <b>Статус загрузки:</b> $UPLOAD_STATUS%0A"
MESSAGE+="🧪 <b>Результат тестирования:</b> $TEST_RESULT%0A"
MESSAGE+="📁 <b>Локальных бэкапов:</b> $TOTAL_BACKUPS%0A"
MESSAGE+="🗑️ <b>Удалено старых:</b> $DELETED_COUNT%0A%0A"
MESSAGE+="🕐 <b>Время:</b> $(date '+%Y-%m-%d %H:%M:%S')"

send_telegram "$MESSAGE"
log "✅ Уведомление отправлено"

log "✅ Резервное копирование завершено успешно!"
log "=========================================="
