FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends cron procps \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir requests

WORKDIR /app

COPY xui_clients_report.py /app/daily_report.py
COPY crontab /etc/cron.d/daily-report
COPY entrypoint.sh /entrypoint.sh

RUN chmod 0644 /etc/cron.d/daily-report && \
    crontab /etc/cron.d/daily-report && \
    touch /var/log/cron.log && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
