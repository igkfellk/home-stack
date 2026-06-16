#!/bin/bash

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════"
echo "  🏠 HOME-STACK МОНИТОРИНГ  $(date '+%Y-%m-%d %H:%M')"
echo "═══════════════════════════════════════════════════════"

echo ""
echo "📦 КОНТЕЙНЕРЫ:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed '1d' | while read line; do
    name=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | awk '{print $2}')
    if [[ "$status" == *"Up"* ]]; then
        echo -e "  ${GREEN}✅${NC} $line"
    else
        echo -e "  ${RED}❌${NC} $line"
    fi
done

echo ""
echo "💾 РАЗМЕР ДАННЫХ:"
printf "  %-15s %10s\n" "📊 Loki:" "$(du -sh ~/home-stack/monitoring/loki-data/ 2>/dev/null | cut -f1 || echo 'N/A')"
printf "  %-15s %10s\n" "📊 Mimir:" "$(du -sh ~/home-stack/monitoring/mimir-data/ 2>/dev/null | cut -f1 || echo 'N/A')"
printf "  %-15s %10s\n" "📊 Prometheus:" "$(du -sh ~/home-stack/monitoring/prometheus-data/ 2>/dev/null | cut -f1 || echo 'N/A')"
printf "  %-15s %10s\n" "📊 MongoDB:" "$(du -sh ~/home-stack/mtg/mongo-data/ 2>/dev/null | cut -f1 || echo 'N/A')"
printf "  %-15s %10s\n" "📊 NPM:" "$(du -sh ~/home-stack/npm/data/ 2>/dev/null | cut -f1 || echo 'N/A')"
printf "  %-15s %10s\n" "📊 Grafana:" "$(du -sh ~/home-stack/monitoring/grafana/ 2>/dev/null | cut -f1 || echo 'N/A')"

echo ""
echo "💿 СВОБОДНО НА ДИСКЕ:"
df -h ~/home-stack | grep -v Filesystem | awk '{print "  " $4 " свободно (" $5 " использовано)"}'

echo ""
echo "📊 RETENTION:"
echo "  ${BLUE}Loki:${NC}       30 дней (720h)"
echo "  ${BLUE}Mimir:${NC}      90 дней (2160h)"
echo "  ${BLUE}Prometheus:${NC} 90 дней / 50GB"

echo ""
echo "📋 СТАТУС RETENTION:"
for service in loki mimir prometheus; do
    case $service in
        loki)
            status=$(docker logs loki 2>&1 | grep -q "compactor is ACTIVE" && echo "✅ Активен" || echo "⏳ Ожидает")
            ;;
        mimir)
            status=$(docker logs mimir 2>&1 | grep -q "successfully compacted" && echo "✅ Активен" || echo "⏳ Ожидает")
            ;;
        prometheus)
            status=$(docker logs prometheus 2>&1 | grep -q "TSDB retention updated" && echo "✅ Активен" || echo "⏳ Ожидает")
            ;;
    esac
    printf "  %-12s %s\n" "$service:" "$status"
done

echo ""
echo "📋 ПОСЛЕДНИЕ ЛОГИ:"
echo -n "  ⏰ Cron Reporter: "
docker logs xui-clients-reporter 2>&1 | tail -1 | cut -c1-50

echo "═══════════════════════════════════════════════════════"
