#!/bin/bash

# Указание проверяемого файла как аргумента командной строки
FILE="$1"

# Проверка на наличие аргумента и существование файла
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: $0 source_file.c"
    exit 1
fi

# Цвета для вывода в терминале
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Массив для накопления ошибок
ERRORS=()

# Проверка наличия необходимых утилит
for cmd in clang-format gcc valgrind awk grep sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Ошибка: утилита '$cmd' не найдена. Установите её для продолжения."
        exit 1
    fi
done

# Предупреждение о пробелах в пути к файлу
if [[ "$FILE" =~ [[:space:]] ]]; then
    echo "Предупреждение: путь к файлу содержит пробелы, что может вызвать проблемы."
fi

# Проверка стиля кода с помощью clang-format
echo -n "Проверка стиля..."
STYLE_CHECK=$(clang-format -n --Werror "$FILE" 2>&1)
if [ $? -ne 0 ]; then
    ERRORS+=("${RED} Ошибки стиля:\n$STYLE_CHECK\nРешение: Используйте 'clang-format -i $FILE' для автоматического исправления.${NC}")
else
    echo -e "${GREEN} Стиль OK.${NC}"
fi

# Проверка наличия глобальных переменных вне функций
echo -n "Проверка глобальных переменных..."
GLOBAL_CHECK=$(awk '
BEGIN { brace_level=0; in_comment=0; in_string=0 }
{
    # Простая обработка комментариев и строк
    line = $0
    gsub(/\/\*.*\*\//, "", line)  # Удаляем однострочные /* */
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)  # Удаляем // комментарии
}
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
    ERRORS+=("${RED} Обнаружены глобальные переменные:\n$GLOBAL_CHECK\nРешение: Перенесите переменные внутрь функций или используйте static/const, если требуется глобальная область видимости.${NC}")
else
    echo -e "${GREEN} Нет глобальных переменных.${NC}"
fi

# Проверка использования оператора 'goto'
echo -n "Проверка использования 'goto'..."
GOTO_CHECK=$(awk '
BEGIN { in_comment=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)  # Удаляем однострочные /* */
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)  # Удаляем // комментарии
    if (match(line, /\bgoto\b/)) print NR ":" $0
}
' "$FILE")
if [ -n "$GOTO_CHECK" ]; then
    ERRORS+=("${RED} Обнаружен оператор 'goto':\n$GOTO_CHECK\nРешение: Замените на структурные конструкции (например, if/while).${NC}")
else
    echo -e "${GREEN} Нет 'goto'.${NC}"
fi

# Проверка использования функции 'exit()'
echo -n "Проверка использования 'exit()'..."
EXIT_CHECK=$(awk '
BEGIN { in_comment=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)  # Удаляем однострочные /* */
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)  # Удаляем // комментарии
    if (match(line, /\bexit\s*\(/)) print NR ":" $0
}
' "$FILE")
if [ -n "$EXIT_CHECK" ]; then
    ERRORS+=("${RED} Используется exit():\n$EXIT_CHECK\nРешение: Не используйте exit(), завершайте функции return'ом.${NC}")
else
    echo -e "${GREEN} Нет exit().${NC}"
fi

# Проверка количества операторов 'return' в функциях
echo -n "Проверка количества return внутри функций..."
RETURN_CHECK=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    f=1; r=0; name=$2; start=NR; delete lines; early_return_allowed=1
}
/}/ {
    if (f && r > 1 && !early_return_allowed) {
        print "Функция " name " (строка " start "): более одного return."
        for (i in lines) print "  return в строке " i ": " lines[i]
    }
    f=0
}
/return/ {
    if (f) {
        r++; lines[NR]=$0
        if (NR - start > 5) early_return_allowed=0
    }
}
' "$FILE")
if [ -n "$RETURN_CHECK" ]; then
    ERRORS+=("${RED} $RETURN_CHECK\nРешение: Убедитесь, что дополнительные return используются только для ранних выходов или реорганизуйте код.${NC}")
else
    echo -e "${GREEN} Return OK.${NC}"
fi

# Проверка глубины вложенности
echo -n "Проверка глубины вложенности..."
MAX_NESTING=$(awk '
BEGIN { level=0; max=0; in_comment=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)  # Удаляем однострочные /* */
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)  # Удаляем // комментарии
    
    # Подсчитываем открывающие и закрывающие скобки
    open_braces = gsub(/{/, "{", line)
    close_braces = gsub(/}/, "}", line)
    level += open_braces - close_braces
    if (level > max) max = level
}
END { print max }
' "$FILE")
if [ "$MAX_NESTING" -gt 4 ]; then
    ERRORS+=("${RED} Глубина вложенности превышает 4 уровня. Найдено: $MAX_NESTING.\nРешение: Упростите структуру кода, вынесите логику в отдельные функции.${NC}")
else
    echo -e "${GREEN} Вложенность OK.${NC}"
fi

# Проверка длины функций
echo -n "Проверка длины функций..."
LONG_FUNCS=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    in_func=1; start=NR; count=0; name=$2
}
/}/ {
    if (in_func) {
        in_func=0
        if (count > 42) {
            print "Функция " name " (начиная с строки " start ") превышает 42 строки (" count ")."
        }
    }
}
in_func && !/^[ \t]*$/ && !/^[ \t]*\/\// {
    count++
}
' "$FILE")
if [ -n "$LONG_FUNCS" ]; then
    ERRORS+=("${RED} $LONG_FUNCS\nРешение: Разбейте функцию на несколько логически завершённых частей.${NC}")
else
    echo -e "${GREEN} Длина функций OK.${NC}"
fi

# Компиляция с проверочными флагами
echo -n "Компиляция с проверочными флагами..."
EXEC="${FILE%.c}.app"
COMPILE_LOG=$(gcc -Wall -Wextra -Wpedantic  "$FILE" -o "$EXEC" 2>&1)
COMPILE_STATUS=$?
if [ $COMPILE_STATUS -ne 0 ]; then
    # Просто выводим исходные ошибки компиляции с рекомендациями
    ERRORS+=("${RED}Ошибки компиляции в файле $FILE:\n$COMPILE_LOG\n\nКак исправить:\n- Неиспользуемые переменные: удалите их или используйте в коде\n- Неиспользуемые параметры: используйте в коде или удалите из функции\n- Другие ошибки: проверьте синтаксис и логику кода${NC}")
else
    echo -e "${GREEN} Компиляция прошла успешно. Файл: $EXEC${NC}"
fi

# Проверка утечек памяти с помощью valgrind, если компиляция успешна
if [ $COMPILE_STATUS -eq 0 ] && [ -f "$EXEC" ]; then
    echo -n "Проверка утечек памяти..."
    VALGRIND_LOG=$(valgrind --leak-check=full --error-exitcode=1 "$EXEC" < /dev/null 2>&1)
    if echo "$VALGRIND_LOG" | grep -q "definitely lost: [^0]"; then
        ERRORS+=("${RED} Обнаружены утечки памяти по данным valgrind:\n$VALGRIND_LOG${NC}")
    else
        echo -e "${GREEN} Утечек памяти не обнаружено.${NC}"
    fi
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