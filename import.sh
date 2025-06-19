#!/bin/bash

# Конфигурация
CSV_PATH="/opt/users.csv"
SEPARATOR=";"
USER_PASSWORD="P@ssw0rd1"
LDB_FILE="/var/lib/samba/private/sam.ldb"

# Проверка файла
if [[ ! -f "$CSV_PATH" ]]; then
    echo "❌ Файл $CSV_PATH не найден"
    exit 1
fi

# Функция очистки данных
clean_field() {
    echo "$1" | tr -d '\r' | sed -e 's/"/\\"/g' -e "s/'/\\'/g" -e 's/\\/\\\\/g' -e 's/`//g'
}

# Функция установки атрибута с повторными попытками
set_attribute() {
    local user_dn="$1"
    local attribute="$2"
    local value="$3"
    
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        if ldbmodify -H "$LDB_FILE" <<EOF >/dev/null 2>&1
dn: $user_dn
changetype: modify
replace: $attribute
$attribute: $value
EOF
        then
            echo "✓ Установлен $attribute"
            return 0
        fi
        
        attempts=$((attempts + 1))
        sleep 0.2
    done
    
    echo "⚠️ Не удалось установить $attribute после $max_attempts попыток"
    return 1
}

# Функция удаления пользователей
delete_existing_users() {
    echo "🗑 ️ Удаление существующих пользователей..."
    while IFS="$SEPARATOR" read -r first_name last_name role phone ou street zip city country _
    do
        first_name=$(echo "$first_name" | tr -d '\r')
        last_name=$(echo "$last_name" | tr -d '\r')

        username="${first_name,,}.${last_name,,}"
        if samba-tool user list | grep -q "^${username}$"; then
            echo "Удаляю: $username"
            samba-tool user delete "$username" >/dev/null 2>&1
        fi
    done < <(tail -n +2 "$CSV_PATH")
    echo "✅ Удаление завершено"
}

# Функция установки атрибутов
set_attributes() {
    local username="$1"
    local ou="$2"
    local street="$3"
    local zip="$4"
    local city="$5"
    
    # Получаем DN пользователя
    user_dn=$(ldbsearch -H "$LDB_FILE" -b "cn=Users,dc=au-team,dc=irpo" "sAMAccountName=$username" dn | grep ^dn: | cut -d' ' -f2-)
    
    if [ -z "$user_dn" ]; then
        echo "❌ Не удалось найти DN для $username"
        return 1
    fi
    
    # Устанавливаем атрибуты с повторными попытками
    set_attribute "$user_dn" "company" "$ou"
    set_attribute "$user_dn" "streetAddress" "$street"
    set_attribute "$user_dn" "postalCode" "$zip"
    set_attribute "$user_dn" "l" "$city"
    set_attribute "$user_dn" "c" "RU"
}

# Функция импорта
import_users() {
    echo "🔄 Импорт пользователей..."
    while IFS="$SEPARATOR" read -r first_name last_name role phone ou street zip city country _
    do
        # Очистка данных
        first_name=$(clean_field "$first_name")
        last_name=$(clean_field "$last_name")
        phone=$(clean_field "$phone")
        ou=$(clean_field "$ou")
        street=$(clean_field "$street")
        zip=$(clean_field "$zip")
        city=$(clean_field "$city")
        
        username="${first_name,,}.${last_name,,}"
        fullname="$first_name $last_name"
        
        echo "➡️ Обработка: $username ($fullname)"
        
        # 1. Создание пользователя
        if ! samba-tool user create "$username" "$USER_PASSWORD" \
            --given-name="$first_name" \
            --surname="$last_name" \
            --telephone-number="$phone"; then
            echo "❌ Ошибка создания $username"
            continue
        fi

        # 2. Базовые настройки
        samba-tool user setexpiry "$username" --noexpiry >/dev/null 2>&1
        
        # 3. Установка атрибутов
        set_attributes "$username" "$ou" "$street" "$zip" "$city"
        
        # 4. Настройка групп
        if [[ -n "$role" ]]; then
            role=$(clean_field "$role")
            if ! samba-tool group list | grep -q "^${role}$"; then
                samba-tool group add "$role" >/dev/null 2>&1
                sleep 0.2
            fi
            samba-tool group addmembers "$role" "$username" >/dev/null 2>&1
        fi

        echo "✅ Успешно: $username"
    done < <(tail -n +2 "$CSV_PATH")
}

# Главный процесс
delete_existing_users
import_users

echo "🎉 Импорт завершен!"