#!/bin/bash

# Указание проверяемого файла
FILE="$1"

# Проверка на наличие аргумента и существование файла
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "Usage: $0 source_file.c"
  exit 1
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Массив для накопления ошибок
ERRORS=()

echo -n "Проверка стиля..."
if ! clang-format -n "$FILE" >/dev/null 2>&1; then
    ERRORS+=("${RED} Ошибки стиля: код не отформатирован. Используйте 'clang-format -i $FILE'.${NC}")
else
    echo -e "${GREEN} Стиль OK.${NC}"
fi

echo -n "Проверка глобальных переменных..."
GLOBAL_CHECK=$(awk '
BEGIN { brace_level=0 }
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    brace_level=1; next
}
/\{/ { brace_level++ }
/\}/ { brace_level-- }
brace_level == 0 && /^[ \t]*(static|const)?[ \t]*(int|char|float|double|long|short|unsigned|signed)[ \t\*]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*(=|;)/ {
    print NR ":" $0
}
' "$FILE")

if [ -n "$GLOBAL_CHECK" ]; then
    ERRORS+=("${RED} Обнаружены глобальные переменные:\n$GLOBAL_CHECK\nРешение: перенесите переменные внутрь функций или используйте static/const, если требуется глобальная область видимости.${NC}")
else
    echo -e "${GREEN} Нет глобальных переменных.${NC}"
fi

echo -n "Проверка использования 'goto'..."
GOTO_CHECK=$(grep -n "\bgoto\b" "$FILE")
if [ -n "$GOTO_CHECK" ]; then
    ERRORS+=("${RED} Обнаружен оператор 'goto':\n$GOTO_CHECK\nРешение: замените на структурные конструкции (например, if/while).${NC}")
else
    echo -e "${GREEN} Нет 'goto'.${NC}"
fi

echo -n "Проверка использования 'exit()'..."
EXIT_CHECK=$(grep -n "\bexit\s*(" "$FILE")
if [ -n "$EXIT_CHECK" ]; then
    ERRORS+=("${RED} Используется exit():\n$EXIT_CHECK\nРешение: не используйте exit(), завершайте функции return'ом.${NC}")
else
    echo -e "${GREEN} Нет exit().${NC}"
fi

echo -n "Проверка количества return внутри функций..."
RETURN_CHECK=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*{/ {
    f=1; r=0; name=$2; start=NR; delete lines
}
/}/ {
    if (f && r > 1) {
        print "Функция " name " (строка " start "): более одного return"
        for (i in lines) print "  return в строке " i ": " lines[i]
    }
    f=0
}
/return/ { if (f) { r++; lines[NR]=$0 } }
' "$FILE")

if [ -n "$RETURN_CHECK" ]; then
    ERRORS+=("${RED} $RETURN_CHECK\nРешение: допускается только один return в теле функции (исключение — проверка аргументов).${NC}")
else
    echo -e "${GREEN} Return OK.${NC}"
fi

echo -n "Проверка глубины вложенности..."
MAX_NESTING=$(awk '
{
    depth = gsub(/{/, "{") - gsub(/}/, "}")
    level += depth
    if (level > max) max = level
}
END { print max }
' "$FILE")

if [ "$MAX_NESTING" -gt 4 ]; then
    ERRORS+=("${RED} Глубина вложенности превышает 4 уровня. Найдено: $MAX_NESTING.${NC}")
else
    echo -e "${GREEN} Вложенность OK.${NC}"
fi

echo -n "Проверка длины функций..."
LONG_FUNCS=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*{/ {
    in_func=1; start=NR; count=1; name=$2; delete lines; lines[start]=$0
    next
}
in_func {
    count++
    lines[NR]=$0
    if (/}/) {
        in_func=0
        if (count > 42) {
            print "Функция " name " (начиная с строки " start ") превышает 42 строки (" count ")."
            for (i in lines) print "  " i ": " lines[i]
        }
    }
}
' "$FILE")

if [ -n "$LONG_FUNCS" ]; then
    ERRORS+=("${RED} $LONG_FUNCS\nРешение: разбейте функцию на несколько логически завершённых частей.${NC}")
else
    echo -e "${GREEN} Длина функций OK.${NC}"
fi

echo -n "Компиляция с проверочными флагами..."
EXEC="${FILE%.c}.app"
COMPILE_LOG=$(gcc -Wall -Wextra -Wpedantic -Werror "$FILE" -o "$EXEC" 2>&1)
if [ $? -ne 0 ]; then
    ERRORS+=("${RED} Ошибка компиляции:\n$COMPILE_LOG${NC}")

else
    echo -e "${GREEN} Компиляция прошла успешно. Файл: $EXEC${NC}"
fi

echo -n "Проверка утечек памяти..."
if [ -f "$EXEC" ]; then
    VALGRIND_LOG=$(valgrind --leak-check=full --error-exitcode=1 "$EXEC" < /dev/null 2>&1)
    if echo "$VALGRIND_LOG" | grep -q "definitely lost: [^0]"; then
        ERRORS+=("${RED} Обнаружены утечки памяти по данным valgrind:\n$VALGRIND_LOG${NC}")
    else
        echo -e "${GREEN} Утечек памяти не обнаружено.${NC}"
    fi
else
    ERRORS+=("${RED} Не удалось найти исполняемый файл '$EXEC' для проверки утечек памяти.${NC}")
fi

# Вывод результатов
echo ""
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}✔ Все проверки пройдены успешно.${NC}"
else
    echo -e "${RED}✘ Найдены проблемы:\n${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "$err"
        echo ""
    done
    exit 1
fi
