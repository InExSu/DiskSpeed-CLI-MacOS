#!/bin/zsh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# По умолчанию
TEST_PATH=""
SIZE_MB=1024

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--path)
      TEST_PATH="$2"
      shift 2
      ;;
    -s|--size)
      SIZE_MB="$2"
      if ! [[ "$SIZE_MB" =~ ^[0-9]+$ ]] || (( SIZE_MB <= 0 )); then
        echo -e "${RED}❌ Размер должен быть положительным целым числом (в МБ).${NC}"
        exit 1
      fi
      shift 2
      ;;
    *)
      echo -e "${RED}❌ Неизвестный аргумент: $1${NC}"
      echo "Использование: $0 [--path ПУТЬ] [--size РАЗМЕР_МБ]"
      exit 1
      ;;
  esac
done

cleanup() {
  if [[ -n ${TEST_FILE:-} && -f "$TEST_FILE" ]]; then
    echo -e "${BLUE}🧹 Удаление временного файла...${NC}"
    rm -f "$TEST_FILE"
  fi
}

trap cleanup EXIT INT TERM

# Если путь не задан — выбираем через Finder
if [[ -z "$TEST_PATH" ]]; then
  echo -e "${BLUE}🖥️  Открывается окно выбора папки...${NC}"
  TEST_PATH=$(
    osascript -e '
      try
        tell application "Finder"
          set folderPath to choose folder with prompt "Выберите том или папку для теста скорости диска:"
        end tell
        POSIX path of folderPath
      on error
        return ""
      end try
    ' 2>/dev/null
  )
  if [[ -z "$TEST_PATH" ]]; then
    echo -e "${RED}❌ Выбор отменён.${NC}"
    exit 1
  fi
fi

# Нормализуем путь
TEST_PATH="${TEST_PATH%/}"
if [[ ! -d "$TEST_PATH" ]]; then
  echo -e "${RED}❌ Путь не существует: $TEST_PATH${NC}"
  exit 1
fi

# Проверка свободного места
FREE_BLOCKS=$(df "$TEST_PATH" | awk 'NR==2 {print $4}')
FREE_MB=$((FREE_BLOCKS * 512 / 1024 / 1024))
REQUIRED_MB=$((SIZE_MB + SIZE_MB / 10))  # +10% запас

if (( FREE_MB < REQUIRED_MB )); then
  echo -e "${RED}❌ Недостаточно места на диске.${NC}"
  echo "Требуется: ~${REQUIRED_MB} МБ, доступно: ${FREE_MB} МБ."
  exit 1
fi

TEST_FILE="$TEST_PATH/.io_test_temp.bin"

echo -e "${GREEN}📁 Путь: $TEST_PATH${NC}"
echo -e "${BLUE}📊 Размер: ${SIZE_MB} МБ${NC}"

# --- Запись ---
echo -e "${BLUE}✍️  Запись ${SIZE_MB} МБ...${NC}"
start_write=$(date +%s)
dd if=/dev/urandom of="$TEST_FILE" bs=1M count="$SIZE_MB" 2>/dev/null
end_write=$(date +%s)

# --- Чтение ---
echo -e "${BLUE}📖 Чтение ${SIZE_MB} МБ...${NC}"
start_read=$(date +%s)
dd if="$TEST_FILE" of=/dev/null bs=1M 2>/dev/null
end_read=$(date +%s)

# --- Расчёт ---
write_time=$((end_write - start_write))
read_time=$((end_read - start_read))

(( write_time == 0 )) && write_time=1
(( read_time == 0 )) && read_time=1

write_speed=$(awk "BEGIN {printf \"%.2f\", $SIZE_MB / $write_time}")
read_speed=$(awk "BEGIN {printf \"%.2f\", $SIZE_MB / $read_time}")

# --- Вывод ---
echo
echo -e "${GREEN}✅ Тест завершён!${NC}"
echo "  💾 Запись: ${write_speed} МБ/с"
echo "  📥 Чтение: ${read_speed} МБ/с"
