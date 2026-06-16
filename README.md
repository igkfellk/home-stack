Отлично! Вот полное описание вашего стека для README.md:

---

# 🏠 Home Stack

Полноценный домашний сервер на Docker Compose с мониторингом, прокси, VPN-сервисами и автоматическими отчетами.

## 📋 Оглавление
- [Архитектура](#-архитектура)
- [Компоненты](#-компоненты)
- [Быстрый старт](#-быстрый-старт)
- [Настройка](#-настройка)
- [Мониторинг](#-мониторинг)
- [Управление](#-управление)
- [Устранение неполадок](#-устранение-неполадок)

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
│   Прокси      │ │   MTProto   │ │                     │
│   (Xray)      │ │   Прокси    │ │                     │
└───────┬───────┘ └─────────────┘ └──────────┬──────────┘
        │                                     │
        ▼                                     ▼
┌───────────────┐                     ┌─────────────────────┐
│   MongoDB     │                     │   PROMETHEUS        │
│   Данные      │                     │   Сбор метрик       │
│   MTG         │                     │                     │
└───────────────┘                     └──────────┬──────────┘
                                                 │
                                                 ▼
                                       ┌─────────────────────┐
                                       │     MIMIR           │
                                       │  Долгосрочное       │
                                       │  хранилище метрик   │
                                       └─────────────────────┘
                                                 │
                                                 ▼
┌─────────────────────────────────────────────────────────────┐
│                     LOKI + PROMTAIL                        │
│              Сбор и хранение логов                         │
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
### 1. Клонировать репозиторий
```bash
git clone https://github.com/igkfellk/home-stack.git
cd home-stack
cp .env.example .env
nano .env  # Заполните своими значениями
docker-compose up -d
./check_stack.sh

### Требования
- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM (рекомендуется 8GB)
- 20GB свободного места на диске

### Установка

```bash
# 1. Клонировать репозиторий
git clone <your-repo-url> ~/home-stack
cd ~/home-stack

# 2. Создать .env файл с переменными
cat > .env << 'EOF'
MTG_HEX_SECRET=your_mtg_secret_here
MTG_MONGO_ROOT_PASS=your_mongo_password
XUI_API_TOKEN=your_xui_api_token
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASS=your_grafana_password
EOF

# 3. Запустить стек
docker-compose up -d

# 4. Проверить статус
docker-compose ps
```

---

## ⚙️ Настройка

### 🔐 Переменные окружения (.env)

Создайте файл `.env` в корне проекта:

```env
# MTG (Telegram MTProto Proxy)
MTG_HEX_SECRET=your_hex_secret_here

# MongoDB
MTG_MONGO_ROOT_PASS=your_secure_password

# 3X-UI API
XUI_API_TOKEN=your_xui_api_token

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASS=your_grafana_password
```

### 📝 Конфигурация сервисов

#### Nginx Proxy Manager
- Веб-интерфейс: `https://your-domain:81`
- Логин по умолчанию: `admin@example.com` / `changeme`

#### 3X-UI
- Веб-интерфейс: `https://your-domain:9443`
- Настройка прокси и пользователей

#### Grafana
- Веб-интерфейс: `https://your-domain:3000`
- Источники данных: Prometheus, Loki, Mimir

### 📊 Политика хранения данных (Retention)

| Сервис | Срок хранения | Настройка |
|--------|---------------|-----------|
| **Loki** | 30 дней | `retention_period: 720h` |
| **Mimir** | 90 дней | `retention_period: 2160h` |
| **Prometheus** | 90 дней / 50GB | `--storage.tsdb.retention.time=90d`<br>`--storage.tsdb.retention.size=50GB` |

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
NAMES     STATUS
npm       Up 2 hours
xui       Up 2 hours
mimir     Up 2 hours
loki      Up 2 hours
prometheus Up 2 hours

💾 РАЗМЕР ДАННЫХ:
  Loki:        156M
  Mimir:       774M
  Prometheus:  539M

💿 СВОБОДНО НА ДИСКЕ:
  15G свободно (65% использовано)

📊 RETENTION:
  Loki:       30 дней (720h)
  Mimir:      90 дней (2160h)
  Prometheus: 90 дней / 50GB
═══════════════════════════════════════════════════════
```

### 📊 Графана Дашборды

Доступны дашборды для:
- **Node Exporter** - системные метрики хоста
- **3X-UI** - статистика клиентов и трафика
- **Loki** - логи всех сервисов
- **Prometheus** - общие метрики

### 🤖 Telegram отчеты

Ежедневно в 9:00 приходит отчет:
```html
📊 ЕЖЕДНЕВНЫЙ ОТЧЕТ ПО КЛИЕНТАМ
📅 Период: 15.06.2026 - 16.06.2026
─────────────────────
👤 client1@example.com
   📥 Загружено: 1.23 GB
   📤 Отдано: 5.67 GB
   📊 Всего: 6.90 GB | 🟢 Online
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

# Просмотр логов
docker logs -f <container_name>

# Обновление образа и перезапуск
docker-compose pull <service_name>
docker-compose up -d <service_name>
```

### Резервное копирование

```bash
# Запуск бэкапа вручную
./backup.sh

# Бэкапы сохраняются в:
ls -lh backups/
# secure-stack_YYYYMMDD_HHMMSS.tar.gz.gpg
```

### Очистка

```bash
# Очистка старых данных
docker system prune -f

# Очистка неиспользуемых образов
docker image prune -f

# Проверка размера данных
./check_stack.sh
```

---

## 🔧 Устранение неполадок

### Контейнер не запускается

```bash
# Посмотреть логи
docker logs <container_name> --tail 50

# Проверить конфиг
docker-compose config
```

### Проблемы с NPM

```bash
# Проверить логи
docker logs npm --tail 50

# Перезапустить
docker-compose restart npm
```

### Проблемы с базами данных

```bash
# Проверить целостность
docker exec mtg-mongo mongosh --eval "db.runCommand({ping: 1})"

# Восстановление из бэкапа
# (см. backup.sh)
```

### Проблемы с retention

```bash
# Проверить работу компактора
docker logs loki | grep -i compactor
docker logs mimir | grep -i compactor

# Проверить размер данных
du -sh monitoring/*-data/
```

---

## 🔒 Безопасность

### Рекомендации
1. ✅ Все сервисы за прокси (NPM) с SSL
2. ✅ Используйте сложные пароли в `.env`
3. ✅ Регулярно обновляйте образы
4. ✅ Настройте фаервол (только порты 80, 443, 8443 открыты)
5. ✅ Включите 2FA для Grafana и NPM
6. ✅ Регулярно делайте бэкапы

### Порты (только необходимые)
| Порт | Сервис | Доступ |
|------|--------|--------|
| 80 | HTTP | 🌐 Внешний |
| 443 | HTTPS | 🌐 Внешний |
| 8443 | MTG | 🌐 Внешний |
| 81 | NPM Admin | 🔒 Внутренний (через прокси) |
| 9443-9449 | 3X-UI | 🔒 Внутренний (через прокси) |
| 3000 | Grafana | 🔒 Внутренний (через прокси) |

---

## 📁 Структура проекта

```
~/home-stack/
├── docker-compose.yml          # Основной конфиг
├── .env                        # Переменные окружения
├── backup.sh                   # Скрипт бэкапа
├── check_stack.sh              # Скрипт мониторинга
├── README.md                   # Документация
│
├── backups/                    # Бэкапы (.tar.gz.gpg)
├── monitoring/                 # Конфиги и данные мониторинга
│   ├── prometheus.yml
│   ├── loki-config.yaml
│   ├── mimir-config.yaml
│   ├── alertmanager.yml
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
└── reports/                    # Отчеты
    └── xui_clients_report.py   # Скрипт отчета
```

---

## 📚 Полезные ссылки

- [Nginx Proxy Manager Docs](https://nginxproxymanager.com/)
- [3X-UI GitHub](https://github.com/MHSanaei/3x-ui)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)
- [Loki Docs](https://grafana.com/docs/loki/)
- [Mimir Docs](https://grafana.com/docs/mimir/)

---

## 📝 Лицензия

MIT License

---

## 👤 Автор

**FellK**

---

**⭐ Не забудьте поставить звезду, если проект был полезен!**

---

## 📊 Статус

![Docker Compose](https://img.shields.io/badge/Docker_Compose-3.8-blue)
![Prometheus](https://img.shields.io/badge/Prometheus-2.45-orange)
![Grafana](https://img.shields.io/badge/Grafana-10.2-blue)
![Loki](https://img.shields.io/badge/Loki-2.9-red)
![Mimir](https://img.shields.io/badge/Mimir-2.11-green)

---
