#!/bin/bash

# Tekshiruvdan o'tkaziladigan faylni buyruq satri argumenti sifatida belgilash
FILE="$1"

# Argument ko‘rsatilganligini va fayl mavjudligini tekshirish
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Foydalanish: $0 source_file.c"
    exit 1
fi

# Terminal uchun rang sozlamalari
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # Rang yo‘q

# Xatoliklar ro‘yxati uchun massiv
ERRORS=()

# Kerakli dasturlarni mavjudligini tekshirish
for cmd in clang-format gcc valgrind awk grep sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Xatolik: '$cmd' utilitasi topilmadi. Davom etish uchun uni o‘rnating."
        exit 1
    fi
done

# Fayl nomida bo‘sh joy borligini tekshirish
if [[ "$FILE" =~ [[:space:]] ]]; then
    echo "Ogohlantirish: Fayl nomida bo‘sh joy mavjud, bu muammoga sabab bo‘lishi mumkin."
fi

# Kod uslubini clang-format bilan tekshirish
echo -n "Uslubni tekshirish..."
STYLE_CHECK=$(clang-format -n --Werror "$FILE" 2>&1)
if [ $? -ne 0 ]; then
    ERRORS+=("${RED} Uslubdagi xatoliklar:\n$STYLE_CHECK\nYechim: 'clang-format -i $FILE' buyrug‘i orqali avtomatik tuzating.${NC}")
else
    echo -e "${GREEN} Uslub OK.${NC}"
fi

# Global o‘zgaruvchilar mavjudligini tekshirish
echo -n "Global o‘zgaruvchilarni tekshirish..."
GLOBAL_CHECK=$(awk '
BEGIN { brace_level=0; in_comment=0; in_string=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)
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
    ERRORS+=("${RED} Global o‘zgaruvchilar topildi:\n$GLOBAL_CHECK\nYechim: O‘zgaruvchilarni funksiyaga joylashtiring yoki static/const dan foydalaning.${NC}")
else
    echo -e "${GREEN} Global o‘zgaruvchi yo‘q.${NC}"
fi

# goto operatoridan foydalanishni tekshirish
echo -n "goto dan foydalanishni tekshirish..."
GOTO_CHECK=$(awk '
BEGIN { in_comment=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)
    if (match(line, /\bgoto\b/)) print NR ":" $0
}
' "$FILE")
if [ -n "$GOTO_CHECK" ]; then
    ERRORS+=("${RED} goto operatori topildi:\n$GOTO_CHECK\nYechim: if/while kabi strukturalardan foydalaning.${NC}")
else
    echo -e "${GREEN} goto yo‘q.${NC}"
fi

# exit() funksiyasidan foydalanishni tekshirish
echo -n "exit() dan foydalanishni tekshirish..."
EXIT_CHECK=$(awk '
BEGIN { in_comment=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)
    if (match(line, /\bexit\s*\(/)) print NR ":" $0
}
' "$FILE")
if [ -n "$EXIT_CHECK" ]; then
    ERRORS+=("${RED} exit() ishlatilgan:\n$EXIT_CHECK\nYechim: exit() o‘rniga return dan foydalaning.${NC}")
else
    echo -e "${GREEN} exit() yo‘q.${NC}"
fi

# return sonini tekshirish
echo -n "Funktsiyadagi return sonini tekshirish..."
RETURN_CHECK=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    f=1; r=0; name=$2; start=NR; delete lines; early_return_allowed=1
}
/}/ {
    if (f && r > 1 && !early_return_allowed) {
        print "Funktsiya " name " (qator " start "): return lar soni 1 dan ortiq."
        for (i in lines) print "  return " i "-qatorda: " lines[i]
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
    ERRORS+=("${RED} $RETURN_CHECK\nYechim: return larni faqat kerakli joylarda ishlating yoki kodni qayta tuzing.${NC}")
else
    echo -e "${GREEN} return OK.${NC}"
fi

# Qavslar orqali chuqurlikni aniqlash
echo -n "Ichma-ichlik chuqurligini tekshirish..."
MAX_NESTING=$(awk '
BEGIN { level=0; max=0; in_comment=0 }
{
    line = $0
    gsub(/\/\*.*\*\//, "", line)
    if (match(line, /\/\*/)) in_comment=1
    if (match(line, /\*\//)) in_comment=0
    if (in_comment) next
    if (match(line, /\/\//)) line = substr(line, 1, RSTART-1)
    open_braces = gsub(/{/, "{", line)
    close_braces = gsub(/}/, "}", line)
    level += open_braces - close_braces
    if (level > max) max = level
}
END { print max }
' "$FILE")
if [ "$MAX_NESTING" -gt 4 ]; then
    ERRORS+=("${RED} Ichma-ichlik 4 dan oshib ketgan: $MAX_NESTING\nYechim: Kodni soddalashtiring yoki funksiyalarga bo‘ling.${NC}")
else
    echo -e "${GREEN} Ichma-ichlik OK.${NC}"
fi

# Funktsiya uzunligini tekshirish
echo -n "Funktsiya uzunligini tekshirish..."
LONG_FUNCS=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    in_func=1; start=NR; count=0; name=$2
}
/}/ {
    if (in_func) {
        in_func=0
        if (count > 42) {
            print "Funktsiya " name " ($start-qator) 42 qatordan uzun: ($count)."
        }
    }
}
in_func && !/^[ \t]*$/ && !/^[ \t]*\/\// {
    count++
}
' "$FILE")
if [ -n "$LONG_FUNCS" ]; then
    ERRORS+=("${RED} $LONG_FUNCS\nYechim: Funktsiyani qismlarga ajrating.${NC}")
else
    echo -e "${GREEN} Funktsiya uzunligi OK.${NC}"
fi

# Kompilyatsiya qilish
echo -n "Kompilyatsiya jarayoni..."
EXEC="${FILE%.c}.app"
COMPILE_LOG=$(gcc -Wall -Wextra -Wpedantic -Werror "$FILE" -o "$EXEC" 2>&1)
COMPILE_STATUS=$?
if [ $COMPILE_STATUS -ne 0 ]; then
    ERRORS+=("${RED}$FILE faylida kompilyatsiya xatolari:\n$COMPILE_LOG\n\nYechimlar:\n- Keraksiz o‘zgaruvchilarni olib tashlang yoki ishlating\n- Keraksiz parametrlarni olib tashlang yoki ishlating\n- Boshqa xatolar: sintaksis va mantiqni tekshiring.${NC}")
else
    echo -e "${GREEN} Kompilyatsiya muvaffaqiyatli. Yaratilgan fayl: $EXEC${NC}"
fi

# Valgrind orqali xotira oqishini tekshirish
if [ $COMPILE_STATUS -eq 0 ] && [ -f "$EXEC" ]; then
    echo -n "Xotira oqishini tekshirish (valgrind)..."
    VALGRIND_LOG=$(valgrind --leak-check=full --error-exitcode=1 "$EXEC" < /dev/null 2>&1)
    if echo "$VALGRIND_LOG" | grep -q "definitely lost: [^0]"; then
        ERRORS+=("${RED} Valgrind natijasiga ko‘ra xotira oqishlari aniqlandi:\n$VALGRIND_LOG${NC}")
    else
        echo -e "${GREEN} Xotira oqishlari aniqlanmadi.${NC}"
    fi
fi

# Yakuniy natijalarni chiqarish
echo ""
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}✔ Barcha tekshiruvlardan muvaffaqiyatli o‘tildi.${NC}"
else
    echo -e "${RED}✘ Muammolar aniqlandi:\n${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "$err"
        echo ""
    done
    exit 1
fi
