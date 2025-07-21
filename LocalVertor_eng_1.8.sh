#!/bin/bash

# Specify the file to check as a command line argument
FILE="$1"

# Check if the argument is given and the file exists
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo "Usage: $0 source_file.c"
    exit 1
fi

# Terminal color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Array to store errors
ERRORS=()

# Check for required utilities
for cmd in clang-format gcc valgrind awk grep sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required utility '$cmd' is not installed. Please install it to continue."
        exit 1
    fi
done

# Warning about spaces in the file path
if [[ "$FILE" =~ [[:space:]] ]]; then
    echo "Warning: the file path contains spaces, which might cause issues."
fi

# Check code style using clang-format
echo -n "Checking style..."
STYLE_CHECK=$(clang-format -n --Werror "$FILE" 2>&1)
if [ $? -ne 0 ]; then
    ERRORS+=("${RED} Style issues found:\n$STYLE_CHECK\nSolution: Run 'clang-format -i $FILE' to fix them automatically.${NC}")
else
    echo -e "${GREEN} Style OK.${NC}"
fi

# Check for global variables outside of functions
echo -n "Checking for global variables..."
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
    ERRORS+=("${RED} Global variables detected:\n$GLOBAL_CHECK\nSolution: Move variables inside functions or use static/const if global scope is required.${NC}")
else
    echo -e "${GREEN} No global variables found.${NC}"
fi

# Check for usage of 'goto'
echo -n "Checking for 'goto' usage..."
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
    ERRORS+=("${RED} 'goto' statement found:\n$GOTO_CHECK\nSolution: Replace with structured control flow (e.g., if/while).${NC}")
else
    echo -e "${GREEN} No 'goto' statements.${NC}"
fi

# Check for usage of 'exit()'
echo -n "Checking for 'exit()' usage..."
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
    ERRORS+=("${RED} Usage of exit() found:\n$EXIT_CHECK\nSolution: Use return instead of exit().${NC}")
else
    echo -e "${GREEN} No exit() calls.${NC}"
fi

# Check number of 'return' statements in functions
echo -n "Checking number of return statements..."
RETURN_CHECK=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    f=1; r=0; name=$2; start=NR; delete lines; early_return_allowed=1
}
/}/ {
    if (f && r > 1 && !early_return_allowed) {
        print "Function " name " (line " start "): more than one return."
        for (i in lines) print "  return at line " i ": " lines[i]
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
    ERRORS+=("${RED} $RETURN_CHECK\nSolution: Use early return only if necessary, otherwise restructure the code.${NC}")
else
    echo -e "${GREEN} Return usage OK.${NC}"
fi

# Check nesting depth
echo -n "Checking nesting depth..."
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
    ERRORS+=("${RED} Nesting depth exceeds 4 levels. Found: $MAX_NESTING\nSolution: Simplify code or break into separate functions.${NC}")
else
    echo -e "${GREEN} Nesting depth OK.${NC}"
fi

# Check function length
echo -n "Checking function length..."
LONG_FUNCS=$(awk '
/^[ \t]*(void|int|char|float|double|long|short|unsigned|signed)[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^)]*\)[ \t]*\{/ {
    in_func=1; start=NR; count=0; name=$2
}
/}/ {
    if (in_func) {
        in_func=0
        if (count > 42) {
            print "Function " name " (starting at line " start ") exceeds 42 lines (" count ")."
        }
    }
}
in_func && !/^[ \t]*$/ && !/^[ \t]*\/\// {
    count++
}
' "$FILE")
if [ -n "$LONG_FUNCS" ]; then
    ERRORS+=("${RED} $LONG_FUNCS\nSolution: Split the function into smaller logical parts.${NC}")
else
    echo -e "${GREEN} Function length OK.${NC}"
fi

# Compile with warning flags
echo -n "Compiling with warning flags..."
EXEC="${FILE%.c}.app"
COMPILE_LOG=$(gcc -Wall -Wextra -Wpedantic  "$FILE" -o "$EXEC" 2>&1)
COMPILE_STATUS=$?
if [ $COMPILE_STATUS -ne 0 ]; then
    ERRORS+=("${RED} Compilation errors in $FILE:\n$COMPILE_LOG\n\nTips:\n- Unused variables: remove or use them\n- Unused parameters: remove or use them\n- Other errors: check syntax and logic.${NC}")
else
    echo -e "${GREEN} Compilation successful. Output: $EXEC${NC}"
fi

# Run valgrind for memory leak check
if [ $COMPILE_STATUS -eq 0 ] && [ -f "$EXEC" ]; then
    echo -n "Checking for memory leaks with valgrind..."
    VALGRIND_LOG=$(valgrind --leak-check=full --error-exitcode=1 "$EXEC" < /dev/null 2>&1)
    if echo "$VALGRIND_LOG" | grep -q "definitely lost: [^0]"; then
        ERRORS+=("${RED} Memory leaks detected by valgrind:\n$VALGRIND_LOG${NC}")
    else
        echo -e "${GREEN} No memory leaks detected.${NC}"
    fi
fi

# Show final results
echo ""
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}✔ All checks passed successfully.${NC}"
else
    echo -e "${RED}✘ Issues found:\n${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "$err"
        echo ""
    done
    exit 1
fi
