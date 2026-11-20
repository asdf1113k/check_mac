#!/bin/bash

cleanup() {
    killall yes afplay say osascript 2>/dev/null
    osascript -e 'tell application "System Events" to set volume output volume 50' 2>/dev/null
    rm -f /tmp/mac_test_rec.m4a /tmp/mac_screen_test.html 2>/dev/null
    echo -e "\nВсе тестовые процессы остановлены, временные файлы удалены."
}
trap cleanup EXIT

clear
echo "=========================================="
echo "    ДИАГНОСТИКА MACBOOK ПЕРЕД ПОКУПКОЙ    "
echo "=========================================="

# 1. Система, батарея и блокировки
echo -e "\n[1/7] ИНФОРМАЦИЯ О СИСТЕМЕ И БЛОКИРОВКАХ:"
SERIAL=$(ioreg -l | grep IOPlatformSerialNumber | awk -F'"' '{print $4}')
CPU=$(sysctl -n machdep.cpu.brand_string)
CYCLES=$(system_profiler SPPowerDataType | grep "Cycle Count" | awk '{print $3}')
CONDITION=$(system_profiler SPPowerDataType | grep "Condition" | awk -F': ' '{print $2}')
CAPACITY=$(system_profiler SPPowerDataType | grep "Maximum Capacity" | awk -F': ' '{print $2}')
MDM_STATUS=$(profiles status -type enrollment 2>/dev/null)

echo "Модель процессора: $CPU"
echo "Серийный номер:    $SERIAL (сверьте с гравировкой на крышке!)"
echo "Циклы батареи:     $CYCLES (Состояние: $CONDITION${CAPACITY:+, Емкость: $CAPACITY})"
echo -e "Проверка MDM (корпоративный контроль):\n$MDM_STATUS"
read -p ">> Нажмите [Enter] для проверки состояния SSD..."

# 2. Проверка состояния SSD и остатка ресурса
echo -e "\n[2/7] ПРОВЕРКА СОСТОЯНИЯ SSD:"
system_profiler SPNVMeDataType | grep -E "Model:|Capacity:|TRIM Support:|S.M.A.R.T. status:" | sed 's/^[ \t]*//'

if command -v smartctl &> /dev/null; then
    echo "--- Детальный ресурс SSD (SMART) ---"
    SMART_DATA=$(smartctl -a /dev/disk0)
    USED_PCT=$(echo "$SMART_DATA" | awk '/Percentage Used:/ {gsub("%",""); print $3}')
    UNITS_WRITTEN=$(echo "$SMART_DATA" | awk '/Data Units Written:/ {gsub(",",""); print $4}')
    POWER_HOURS=$(echo "$SMART_DATA" | awk '/Power On Hours:/ {gsub(",",""); print $4}')

    if [ -n "$USED_PCT" ] && [ -n "$UNITS_WRITTEN" ]; then
        # 1 Data Unit = 512,000 байт. Переводим в Терабайты (1 ТБ = 10^12 байт)
        TB_WRITTEN=$(awk "BEGIN {printf \"%.2f\", ($UNITS_WRITTEN * 512000) / 1000000000000}")
        HEALTH_LEFT=$((100 - USED_PCT))

        echo "Здоровье SSD:      $HEALTH_LEFT% (Износ: $USED_PCT%)"
        echo "Уже записано:      $TB_WRITTEN ТБ (Время работы: ${POWER_HOURS:-н/д} ч.)"

        if [ "$USED_PCT" -gt 0 ]; then
            TB_REMAINING=$(awk "BEGIN {printf \"%.2f\", ($TB_WRITTEN / $USED_PCT) * $HEALTH_LEFT}")
            echo "Осталось записать: ~$TB_REMAINING ТБ (до исчерпания 100% ресурса TBW)"
        else
            echo "Осталось записать: почти 100% заводского ресурса (износ пока 0%)"
        fi
    else
        echo "$SMART_DATA" | grep -E "Percentage Used|Data Units Written|Power On Hours"
    fi
else
    echo "⚠️  Точный износ и остаток ТБ недоступны: не установлена утилита smartctl."
    echo "   Базовый статус 'Verified' означает лишь отсутствие критических сбоев."
    echo "   Если есть интернет и Homebrew, установите её командой: brew install smartmontools"
fi
read -p ">> Нажмите [Enter] для проверки экрана на битые пиксели..."

# 3. Проверка экрана на битые пиксели и засветы
echo -e "\n[3/7] ПРОВЕРКА ЭКРАНА:"
cat << 'EOF' > /tmp/mac_screen_test.html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Проверка экрана MacBook</title>
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; cursor: pointer; font-family: -apple-system, sans-serif; }
  #hint { position: fixed; top: 20px; left: 50%; transform: translateX(-50%); background: rgba(0,0,0,0.75); color: #fff; padding: 12px 24px; border-radius: 8px; font-size: 16px; pointer-events: none; transition: opacity 0.5s; }
</style>
</head>
<body style="background-color: #FF0000;" onclick="nextColor()">
<div id="hint">Нажимайте ПРОБЕЛ или кликайте мышью для смены цвета (Красный -> Зеленый -> Синий -> Белый -> Черный).<br>Для полноэкранного режима нажмите Cmd + Ctrl + F.</div>
<script>
  const colors = ['#FF0000', '#00FF00', '#0000FF', '#FFFFFF', '#000000'];
  let idx = 0;
  function nextColor() {
    idx = (idx + 1) % colors.length;
    document.body.style.backgroundColor = colors[idx];
    document.getElementById('hint').style.opacity = '0';
  }
  document.addEventListener('keydown', (e) => {
    if (e.code === 'Space' || e.code === 'ArrowRight') nextColor();
  });
</script>
</body>
</html>
EOF

open /tmp/mac_screen_test.html
echo "В браузере открыт тест экрана."
echo "1. Разверните окно на весь экран (Cmd + Ctrl + F)."
echo "2. Нажимайте ПРОБЕЛ для переключения цветов и осмотрите матрицу."
read -p ">> Осмотрели экран? Вернитесь в Терминал и нажмите [Enter] для проверки Wi-Fi и Bluetooth..."

# 4. Проверка Wi-Fi и Bluetooth
echo -e "\n[4/7] ПРОВЕРКА БЕСПРОВОДНЫХ МОДУЛЕЙ:"
WIFI_PORT=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
WIFI_STATUS=$(networksetup -getairportpower "$WIFI_PORT" 2>/dev/null)
BT_STATUS=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -E "State:|Bluetooth Power:" | head -n 1 | xargs)

echo "Wi-Fi ($WIFI_PORT): ${WIFI_STATUS:-Модуль не найден}"
echo "Bluetooth:     ${BT_STATUS:-Статус не определен (проверьте в Пункте управления)}"
echo "Поиск Wi-Fi сетей поблизости (проверка антенны):"
system_profiler SPAirPortDataType | grep -A 5 "Other Local Wi-Fi Networks:" | head -n 6
read -p ">> Нажмите [Enter] для проверки динамиков..."

# 5. Проверка динамиков
echo -e "\n[5/7] ПРОВЕРКА ДИНАМИКОВ:"
osascript -e "set volume output volume 80"
echo "Воспроизвожу тестовый звук (слушайте оба канала на предмет хрипов)..."
(
    while true; do
        afplay /System/Library/Sounds/Ping.aiff
        say -v Milena "Проверка динамиков. Левый и правый канал." 2>/dev/null || say "Testing speakers."
        sleep 0.5
    done
) &
SOUND_PID=$!
read -p ">> Нажмите [Enter], чтобы остановить звук и перейти к микрофону..."
kill $SOUND_PID 2>/dev/null
killall afplay say 2>/dev/null

# 6. Проверка микрофона
echo -e "\n[6/7] ПРОВЕРКА МИКРОФОНА:"
echo "Сейчас откроется QuickTime. Если появится запрос доступа к микрофону или управлению — нажмите «Разрешить»."
rm -f /tmp/mac_test_rec.m4a
osascript <<EOF
tell application "QuickTime Player"
    activate
    set newRecording to new audio recording
    start newRecording
end tell
EOF
read -p ">> ГОВОРИТЕ В МИКРОФОН 3-5 секунд. Затем нажмите [Enter] для прослушивания..."
osascript <<EOF
tell application "QuickTime Player"
    stop document 1
    export document 1 in POSIX file "/tmp/mac_test_rec.m4a" using settings preset "Audio Only"
    close document 1 saving no
    quit
end tell
EOF
echo "Воспроизвожу вашу запись..."
afplay /tmp/mac_test_rec.m4a &
PLAY_PID=$!
read -p ">> Нажмите [Enter], чтобы перейти к СТРЕСС-ТЕСТУ процессора и видеокарты..."
kill $PLAY_PID 2>/dev/null

# 7. Стресс-тест CPU и GPU
echo -e "\n[7/7] СТРЕСС-ТЕСТ CPU И GPU:"
THREADS=$(sysctl -n hw.ncpu)
echo "Запускаю 100% нагрузку на все потоки процессора ($THREADS шт.)..."
for i in $(seq 1 $THREADS); do
    yes > /dev/null &
done
echo "Открываю 3D-сцену WebGL Aquarium для нагрузки на видеокарту..."
open "https://webglsamples.org" 2>/dev/null

echo -e "\n🔥 ТЕСТ ИДЁТ! Следите 3–5 минут за шумом кулеров, нагревом и стабильностью."
echo "В открывшейся вкладке браузера выберите слева 'Number of Fish: 10000' или '30000'."
read -p ">> Нажмите [Enter], чтобы ОСТАНОВИТЬ стресс-тест и завершить проверку..."

