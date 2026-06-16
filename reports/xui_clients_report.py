import requests
from datetime import datetime, timedelta
import os
import sys

# --- КОНФИГУРАЦИЯ из .env ---
PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://prometheus:9090')

# ОБЯЗАТЕЛЬНЫЕ переменные окружения
TELEGRAM_BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
TELEGRAM_CHAT_ID = os.getenv('TG_CHAT_ID')
TELEGRAM_THREAD_ID = os.getenv('TG_THREAD_ID')

# Проверка наличия обязательных переменных
if not TELEGRAM_BOT_TOKEN:
    print("❌ Ошибка: TG_BOT_TOKEN не задан в .env")
    sys.exit(1)
if not TELEGRAM_CHAT_ID:
    print("❌ Ошибка: TG_CHAT_ID не задан в .env")
    sys.exit(1)

# Конвертируем THREAD_ID в int, если он задан
try:
    TELEGRAM_THREAD_ID = int(TELEGRAM_THREAD_ID) if TELEGRAM_THREAD_ID else None
except ValueError:
    print(f"❌ Ошибка: TG_THREAD_ID должен быть числом, получено: {TELEGRAM_THREAD_ID}")
    sys.exit(1)

# --- ФУНКЦИЯ ЗАПРОСА К PROMETHEUS ---
def query_prometheus(query):
    """Выполняет запрос к Prometheus и возвращает результат."""
    try:
        response = requests.get(
            f'{PROMETHEUS_URL}/api/v1/query',
            params={'query': query},
            timeout=30
        )
        response.raise_for_status()
        data = response.json()
        if data['status'] != 'success':
            raise Exception(f"Prometheus query failed: {data}")
        return data['data']['result']
    except requests.exceptions.RequestException as e:
        raise Exception(f"Ошибка подключения к Prometheus: {e}")

# --- ФОРМИРОВАНИЕ ОТЧЕТА ---
def generate_report():
    """Генерирует текстовый отчет по клиентам за последние 24 часа."""
    # 1. Получаем данные по трафику для каждого клиента за 24 часа
    query_up = 'sum(increase(xui_client_up_bytes_total[24h])) by (email)'
    query_down = 'sum(increase(xui_client_down_bytes_total[24h])) by (email)'
    
    up_data = {item['metric']['email']: float(item['value'][1]) for item in query_prometheus(query_up)}
    down_data = {item['metric']['email']: float(item['value'][1]) for item in query_prometheus(query_down)}

    # 2. Получаем статус онлайн для каждого клиента
    query_online = 'xui_client_online'
    online_data = {item['metric']['email']: int(float(item['value'][1])) for item in query_prometheus(query_online)}

    # 3. Собираем всех клиентов
    all_emails = set(up_data.keys()) | set(down_data.keys()) | set(online_data.keys())
    
    if not all_emails:
        return "📊 За последние 24 часа нет данных по клиентам."

    # 4. Формируем тело отчета
    report_lines = [
        f"📊 <b>ЕЖЕДНЕВНЫЙ ОТЧЕТ ПО КЛИЕНТАМ</b>",
        f"📅 Период: {(datetime.now() - timedelta(days=1)).strftime('%d.%m.%Y')} - {datetime.now().strftime('%d.%m.%Y')}",
        "─────────────────────"
    ]

    # Сортируем клиентов по сумме трафика (по убыванию)
    sorted_emails = sorted(all_emails, key=lambda email: up_data.get(email, 0) + down_data.get(email, 0), reverse=True)

    for email in sorted_emails:
        up_bytes = up_data.get(email, 0)
        down_bytes = down_data.get(email, 0)
        total_mb = (up_bytes + down_bytes) / (1024 * 1024)
        status = "🟢 Online" if online_data.get(email, 0) == 1 else "🔴 Offline"
        
        # Форматируем трафик в ГБ или МБ
        if total_mb > 1024:
            traffic_str = f"{total_mb / 1024:.2f} GB"
        else:
            traffic_str = f"{total_mb:.2f} MB"

        report_lines.append(
            f"👤 <b>{email}</b>\n"
            f"   📥 Загружено: {down_bytes / (1024*1024):.2f} MB\n"
            f"   📤 Отдано: {up_bytes / (1024*1024):.2f} MB\n"
            f"   📊 Всего: {traffic_str} | {status}"
        )

    report_lines.append("─────────────────────")
    report_lines.append("📌 Отчет сгенерирован автоматически.")
    
    return "\n".join(report_lines)

# --- ОТПРАВКА В TELEGRAM ---
def send_telegram_message(text):
    """Отправляет сообщение в Telegram."""
    url = f'https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage'
    payload = {
        'chat_id': TELEGRAM_CHAT_ID,
        'text': text,
        'parse_mode': 'HTML',
    }
    if TELEGRAM_THREAD_ID:
        payload['message_thread_id'] = TELEGRAM_THREAD_ID
    
    try:
        response = requests.post(url, json=payload, timeout=10)
        response.raise_for_status()
        print("✅ Отчет отправлен в Telegram")
    except requests.exceptions.RequestException as e:
        raise Exception(f"Ошибка отправки в Telegram: {e}")

# --- ГЛАВНАЯ ФУНКЦИЯ ---
def main():
    try:
        print("🔄 Генерация отчета...")
        report = generate_report()
        print("📤 Отправка в Telegram...")
        send_telegram_message(report)
        print("✅ Готово!")
    except Exception as e:
        error_message = f"❌ <b>Ошибка при генерации отчета</b>\n{str(e)}"
        try:
            send_telegram_message(error_message)
        except:
            print(f"❌ Критическая ошибка: {e}")
        print(f"❌ Ошибка: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
