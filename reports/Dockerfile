FROM python:3.11-slim

RUN apt-get update && apt-get install -y cron && \
    pip install requests && \
    rm -rf /var/lib/apt/lists/*

COPY xui_clients_report.py /app/daily_report.py
WORKDIR /app

# Каждый день в 9:00
RUN echo "0 9 * * * cd /app && python3 /app/daily_report.py >> /var/log/cron.log 2>&1" > /etc/cron.d/daily-report && \
    chmod 0644 /etc/cron.d/daily-report && \
    touch /var/log/cron.log

CMD ["cron", "-f"]
