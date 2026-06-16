```markdown
# 🏠 Home Stack

Полноценный домашний сервер на Docker Compose с мониторингом, прокси, VPN-сервисами и автоматическими отчетами.

[![Docker Compose](https://img.shields.io/badge/Docker_Compose-3.8-blue)](https://docs.docker.com/compose/)
[![Prometheus](https://img.shields.io/badge/Prometheus-2.45-orange)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-10.2-blue)](https://grafana.com/)
[![Loki](https://img.shields.io/badge/Loki-2.9-red)](https://grafana.com/oss/loki/)
[![Mimir](https://img.shields.io/badge/Mimir-2.11-green)](https://grafana.com/oss/mimir/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## 📋 Оглавление
- [Особенности](#-особенности)
- [Архитектура](#-архитектура)
- [Компоненты](#-компоненты)
- [Быстрый старт](#-быстрый-старт)
- [Настройка](#-настройка)
- [Мониторинг](#-мониторинг)
- [Управление](#-управление)
- [Безопасность](#-безопасность)
- [Устранение неполадок](#-устранение-неполадок)
- [Лицензия](#-лицензия)

---

## ✨ Особенности

- 🔒 **Безопасный доступ** — все сервисы за Nginx Proxy Manager с автоматическими SSL-сертификатами
- 📊 **Полный мониторинг** — Prometheus + Grafana + Loki + Mimir
- 📈 **Долгосрочное хранение** — метрики хранятся 90 дней, логи — 30 дней
- 🤖 **Автоматизация** — ежедневные отчеты в Telegram и автоматические бэкапы
- 🚀 **Легкое развертывание** — все в одном docker-compose.yml
- 🔐 **Безопасность** — все секреты в .env, не в репозитории

---

## 🏗 Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                      ВНЕШНИЙ МИР                          │
│                  (Интернет / Пользователи)                  │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              NGINX PROXY MANAGER (npm)                     │
│          Обратный прокси + SSL (LetsEncrypt)               │
│                  Порты: 80, 443, 81                        │
└───────┬──────────────┬──────────────┬─────────────────────┘
        │              │              │
        ▼              ▼              ▼
┌───────────────┐ ┌─────────────┐ ┌─────────────────────┐
│   3X-UI       │ │    MTG      │ │    GRAFANA          │
│   Панель      │ │   Telegram  │ │   Визуализация      │
│   Прокси      │ │   MTProto   │ │   (3000)            │
│   (Xray)      │ │   (8443)    │ │                     │
└───────┬───────┘ └─────────────┘ └──────────┬──────────┘
        │                                     │
        ▼                                     ▼
┌───────────────┐                     ┌─────────────────────┐
│   MongoDB     │                     │   PROMETHEUS        │
│   Данные      │                     │   Сбор метрик       │
│   MTG         │                     │   (9090)            │
└───────────────┘                     └──────────┬──────────┘
                                                 │
                                                 ▼
                                       ┌─────────────────────┐
                                       │     MIMIR           │
                                       │  Долгосрочное       │
                                       │  хранилище метрик   │
                                       │  (8080)            │
                                       └─────────────────────┘
                                                 │
                                                 ▼
┌─────────────────────────────────────────────────────────────┐
│                     LOKI + PROMTAIL                        │
│              Сбор и хранение логов (3100)                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧩 Компоненты

### 🌐 Прокси и доступ
| Сервис | Контейнер | Порт | Описание |
|--------|-----------|------|----------|
| **Nginx Proxy Manager** | `npm` | 80, 443, 81 | Обратный прокси с автоматическими SSL-сертификатами |
| **3X-UI** | `xui` | 9443-9449 | Панель управления Xray/V2Ray прокси |
| **MTG** | `mtg` | 8443 | Telegram MTProto прокси |

### 📊 Мониторинг
| Сервис | Контейнер | Порт | Описание |
|--------|-----------|------|----------|
| **Prometheus** | `prometheus` | 9090 | Сбор и хранение метрик (90 дней) |
| **Grafana** | `grafana` | 3000 | Визуализация метрик и логов |
| **Loki** | `loki` | 3100 | Хранилище логов (30 дней) |
| **Promtail** | `promtail` | - | Агент сбора логов |
| **Mimir** | `mimir` | 8080 | Долгосрочное хранилище метрик (90 дней) |
| **AlertManager** | `alertmanager` | 9093 | Управление алертами |
| **Node Exporter** | `node-exporter` | 9100 | Метрики хоста |

### 📦 Базы данных
| Сервис | Контейнер | Порт | Описание |
|--------|-----------|------|----------|
| **MongoDB** | `mtg-mongo` | 27017 | Данные MTG прокси |

### 🤖 Автоматизация
| Сервис | Контейнер | Описание |
|--------|-----------|----------|
| **XUI API Exporter** | `xui-api-exporter` | Экспортер метрик из 3X-UI в Prometheus |
| **XUI Clients Reporter** | `xui-clients-reporter` | Ежедневный отчет по клиентам в Telegram |

---

## 🚀 Быстрый старт

### Требования
- **Docker** 20.10+
- **Docker Compose** 2.0+
- **4GB RAM** (рекомендуется 8GB)
- **20GB** свободного места на диске
- **Домен** (опционально, для SSL)

### Установка

```bash
# 1. Клонировать репозиторий
git clone https://github.com/igkfellk/home-stack.git
cd home-stack

# 2. Создать .env файл из шаблона
cp .env.example .env
nano .env  # Заполните своими значениями

# 3. Запустить стек
docker-compose up -d

# 4. Проверить статус
./check_stack.sh
```

### Настройка .env

Создайте файл `.env` в корне проекта:

```env
# --- MTG (Telegram MTProto Proxy) ---
# Получить: https://core.telegram.org/getting-started#creating-a-secret
MTG_HEX_SECRET=your_hex_secret_here

# --- MongoDB ---
# Сгенерировать: openssl rand -base64 32
MTG_MONGO_ROOT_PASS=your_secure_password_here

# --- 3X-UI API ---
# Получить в панели 3X-UI: Настройки → API
XUI_API_TOKEN=your_xui_api_token_here

# --- XUI Domain (для монтирования сертификатов) ---
XUI_DOMAIN=xui.your-domain.com

# --- Grafana ---
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASS=your_grafana_secure_password_here

# --- Telegram Reports ---
# Создать бота: @BotFather в Telegram
TG_BOT_TOKEN=your_telegram_bot_token_here
# ID чата: @userinfobot или @getmyid_bot
TG_CHAT_ID=your_telegram_chat_id_here
# ID топика (опционально, если используете форумы)
TG_THREAD_ID=your_telegram_thread_id_here
# Для алертов (можно использовать тот же или отдельный)
TG_THREAD_ID_ALERTS=your_telegram_thread_id_for_alerts
```

---

## ⚙️ Настройка

### 📝 Конфигурация сервисов

#### Nginx Proxy Manager
- Веб-интерфейс: `https://your-domain:81`
- Логин по умолчанию: `admin@example.com` / `changeme`
- После входа сразу смените пароль!

#### 3X-UI
- Веб-интерфейс: `https://your-domain:9443`
- Настройка прокси и пользователей
- API токен для экспортера: Настройки → API

#### Grafana
- Веб-интерфейс: `https://your-domain:3000`
- Источники данных: Prometheus, Loki, Mimir
- Дашборды импортируются автоматически

### 📊 Политика хранения данных (Retention)

| Сервис | Срок хранения | Настройка | Локация |
|--------|---------------|-----------|---------|
| **Loki** | 30 дней | `retention_period: 720h` | `monitoring/loki-config.yaml` |
| **Mimir** | 90 дней | `retention_period: 2160h` | `monitoring/mimir-config.yaml` |
| **Prometheus** | 90 дней / 50GB | `--storage.tsdb.retention.time=90d`<br>`--storage.tsdb.retention.size=50GB` | `docker-compose.yml` |

---

## 📈 Мониторинг

### Скрипт проверки состояния

```bash
./check_stack.sh
```

Вывод:
```
═══════════════════════════════════════════════════════
  🏠 HOME-STACK МОНИТОРИНГ  2026-06-16 09:30
═══════════════════════════════════════════════════════

📦 КОНТЕЙНЕРЫ:
  ✅ xui-clients-reporter   Up 2 hours
  ✅ npm                    Up 3 hours
  ✅ xui                    Up 3 hours
  ✅ mimir                  Up 3 hours
  ✅ loki                   Up 3 hours
  ✅ prometheus             Up 3 hours
  ✅ grafana                Up 3 hours
  ✅ alertmanager           Up 3 hours
  ✅ mtg                    Up 3 hours
  ✅ mtg-mongo              Up 3 hours
  ✅ node-exporter          Up 3 hours
  ✅ promtail               Up 3 hours
  ✅ xui-api-exporter       Up 3 hours

💾 РАЗМЕР ДАННЫХ:
  📊 Loki:             27M
  📊 Mimir:           677M
  📊 Prometheus:       543M
  📊 MongoDB:         356K
  📊 NPM:             3.3M
  📊 Grafana:         101M

💿 СВОБОДНО НА ДИСКЕ:
  124G свободно (17% использовано)

📊 RETENTION:
  Loki:       30 дней (720h)
  Mimir:      90 дней (2160h)
  Prometheus: 90 дней / 50GB

📋 СТАТУС RETENTION:
  loki:        ✅ Активен
  mimir:       ✅ Активен
  prometheus:  ✅ Активен
═══════════════════════════════════════════════════════
```

### 📊 Grafana Дашборды

Доступны дашборды для:
- **Node Exporter** — системные метрики хоста (CPU, RAM, Disk, Network)
- **3X-UI** — статистика клиентов и трафика
- **Loki** — логи всех сервисов
- **Prometheus** — общие метрики

### 🤖 Telegram отчеты

Ежедневно в 9:00 приходит отчет:

```
📊 ЕЖЕДНЕВНЫЙ ОТЧЕТ ПО КЛИЕНТАМ
📅 Период: 15.06.2026 - 16.06.2026
─────────────────────
👤 client1@example.com
   📥 Загружено: 1.23 GB
   📤 Отдано: 5.67 GB
   📊 Всего: 6.90 GB | 🟢 Online
─────────────────────
👤 client2@example.com
   📥 Загружено: 0.45 GB
   📤 Отдано: 0.12 GB
   📊 Всего: 0.57 GB | 🔴 Offline
─────────────────────
📌 Отчет сгенерирован автоматически.
```

---

## 🛠 Управление

### Основные команды

```bash
# Запуск всех сервисов
docker-compose up -d

# Остановка всех сервисов
docker-compose down

# Перезапуск конкретного сервиса
docker-compose restart <service_name>

# Просмотр логов всех сервисов
docker-compose logs -f

# Просмотр логов конкретного сервиса
docker logs -f <container_name>

# Обновление образа и перезапуск
docker-compose pull <service_name>
docker-compose up -d <service_name>

# Проверка состояния
./check_stack.sh
```

### 💾 Резервное копирование

```bash
# Запуск бэкапа вручную
./backup.sh

# Бэкапы сохраняются в:
ls -lh backups/
# secure-stack_YYYYMMDD_HHMMSS.tar.gz.gpg

# Восстановление из бэкапа
gpg -d backups/secure-stack_*.tar.gz.gpg | tar -xz
```

### 🧹 Очистка

```bash
# Очистка старых данных Docker
docker system prune -f

# Очистка неиспользуемых образов
docker image prune -f

# Очистка остановленных контейнеров
docker container prune -f

# Проверка размера данных
./check_stack.sh
```

---

## 🔒 Безопасность

### Рекомендации

1. ✅ Все сервисы за прокси (NPM) с SSL
2. ✅ Используйте сложные пароли в `.env`
3. ✅ Регулярно обновляйте образы: `docker-compose pull`
4. ✅ Настройте фаервол (только порты 80, 443, 8443 открыты)
5. ✅ Включите 2FA для Grafana и NPM
6. ✅ Регулярно делайте бэкапы: `./backup.sh`
7. ✅ Не коммитьте `.env` и другие sensitive файлы

### Порты (только необходимые)

| Порт | Сервис | Доступ | Назначение |
|------|--------|--------|------------|
| 80 | HTTP | 🌐 Внешний | Редирект на HTTPS |
| 443 | HTTPS | 🌐 Внешний | Основной веб-трафик |
| 8443 | MTG | 🌐 Внешний | Telegram MTProto |
| 81 | NPM Admin | 🔒 Внутренний | Админка (через прокси) |
| 9443-9449 | 3X-UI | 🔒 Внутренний | Панель XUI (через прокси) |
| 3000 | Grafana | 🔒 Внутренний | Дашборды (через прокси) |
| 9090 | Prometheus | 🔒 Внутренний | Метрики (через прокси) |
| 3100 | Loki | 🔒 Внутренний | Логи (через прокси) |
| 8080 | Mimir | 🔒 Внутренний | Хранилище (через прокси) |

---

## 🔧 Устранение неполадок

### Контейнер не запускается

```bash
# Посмотреть логи
docker logs <container_name> --tail 50

# Проверить конфиг
docker-compose config

# Проверить переменные в .env
docker-compose config | grep -i <service_name>
```

### Проблемы с NPM

```bash
# Проверить логи
docker logs npm --tail 50

# Перезапустить
docker-compose restart npm

# Проверить порты
sudo netstat -tlnp | grep -E "80|443|81"
```

### Проблемы с 3X-UI

```bash
# Проверить логи
docker logs xui --tail 50

# Проверить API токен в .env
grep XUI_API_TOKEN .env

# Перезапустить
docker-compose restart xui
```

### Проблемы с базами данных

```bash
# Проверить целостность MongoDB
docker exec mtg-mongo mongosh --eval "db.runCommand({ping: 1})"

# Проверить логи MongoDB
docker logs mtg-mongo --tail 50

# Восстановление из бэкапа
# (см. backup.sh)
```

### Проблемы с retention

```bash
# Проверить работу компактора Loki
docker logs loki 2>&1 | grep -i "compactor\|retention"

# Проверить работу компактора Mimir
docker logs mimir 2>&1 | grep -i "compactor\|retention"

# Проверить размер данных
du -sh monitoring/*-data/ 2>/dev/null
```

### Проблемы с Telegram отчетами

```bash
# Проверить логи репортера
docker logs xui-clients-reporter

# Проверить переменные в .env
grep TG_ .env

# Запустить вручную
docker exec xui-clients-reporter python3 /app/daily_report.py
```

---

## 📁 Структура проекта

```
~/home-stack/
├── docker-compose.yml          # Основной конфиг
├── .env                        # Переменные окружения (НЕ В GIT!)
├── .env.example                # Шаблон .env
├── .gitignore                  # Исключения для Git
├── backup.sh                   # Скрипт бэкапа
├── check_stack.sh              # Скрипт мониторинга
├── LICENSE                     # MIT License
├── README.md                   # Документация
│
├── backups/                    # Бэкапы (.tar.gz.gpg)
├── monitoring/                 # Конфиги и данные мониторинга
│   ├── prometheus.yml
│   ├── prometheus-auth         # ⚠️ НЕ В GIT (пароль)
│   ├── alertmanager.yml        # ⚠️ НЕ В GIT (токен)
│   ├── alertmanager.yml.example
│   ├── alerts.yml
│   ├── loki-config.yaml
│   ├── mimir-config.yaml
│   ├── promtail-config.yaml
│   ├── prometheus-data/        # Данные Prometheus
│   ├── loki-data/              # Данные Loki
│   ├── mimir-data/             # Данные Mimir
│   └── grafana/                # Данные Grafana
├── npm/                        # Nginx Proxy Manager
│   ├── data/                   # Конфиги и БД
│   └── letsencrypt/            # SSL сертификаты
├── xui/                        # 3X-UI
│   ├── db/                     # БД XUI
│   └── cert/                   # Сертификаты
├── mtg/                        # MTG
│   └── mongo-data/             # Данные MongoDB
├── reports/                    # Отчеты
│   ├── Dockerfile
│   └── xui_clients_report.py
└── xui-api-exporter-repo/      # Субмодуль (xui-api-exporter)
    ├── Dockerfile
    └── xui-exporter.py
```

---

## 📚 Полезные ссылки

- [Nginx Proxy Manager Docs](https://nginxproxymanager.com/)
- [3X-UI GitHub](https://github.com/MHSanaei/3x-ui)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)
- [Loki Docs](https://grafana.com/docs/loki/)
- [Mimir Docs](https://grafana.com/docs/mimir/)
- [MTG (Telegram MTProto) GitHub](https://github.com/9seconds/mtg)

---

## 📝 Лицензия

MIT License. См. файл [LICENSE](LICENSE).

---

## 👤 Автор

**FellK**

- GitHub: [@igkfellk](https://github.com/igkfellk)
- Репозиторий: [home-stack](https://github.com/igkfellk/home-stack)

---

## ⭐ Поддержка

Если этот проект был полезен, поставьте звезду на GitHub!

[![Star on GitHub](https://img.shields.io/github/stars/igkfellk/home-stack?style=social)](https://github.com/igkfellk/home-stack)

---

**⭐ Не забудьте поставить звезду, если проект был полезен!**
```

---

## 📋 Что добавлено/исправлено

| Добавлено | Описание |
|-----------|----------|
| ✅ **Бейджи статуса** | В начале README для красоты |
| ✅ **Особенности** | Список ключевых фич |
| ✅ **XUI_DOMAIN** | Добавлена переменная для домена |
| ✅ **Все переменные .env** | Полный список с комментариями |
| ✅ **AlertManager токен** | Документация для алертов |
| ✅ **Очистка** | Команды docker prune |
| ✅ **Восстановление из бэкапа** | Команда для восстановления |
| ✅ **Проблемы с 3X-UI** | Раздел устранения неполадок |
| ✅ **Проблемы с Telegram** | Раздел устранения неполадок |
| ✅ **Структура** | Добавлены файлы ⚠️ НЕ В GIT |
| ✅ **Ссылки** | Добавлен MTG GitHub |
| ✅ **Порты** | Добавлены порты для мониторинга |
| ✅ **Автор** | Контактные данные |
| ✅ **Поддержка** | Кнопка Star на GitHub |

---
