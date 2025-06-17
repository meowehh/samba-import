#!/bin/bash

# Конфигурация
CSV_PATH="$1"
SEPARATOR=";"
DOMAIN="au-team.irpo"
ADMIN_USER="Administrator"
ADMIN_PASS="P@ssw0rd"

# Проверка файла
if [[ ! -f "$CSV_PATH" ]]; then
    echo "❌ Файл $CSV_PATH не найден"
    exit 1
fi

# Функция удаления пользователей из CSV
delete_existing_users() {
    echo "🗑️ Начинаю удаление пользователей из CSV..."
    while IFS="$SEPARATOR" read -r first_name last_name role phone ou street zip city country password
    do
        username=$(echo "${first_name:0:1}${last_name}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alpha:]')
        
        if samba-tool user list | grep -q "^${username}$"; then
            echo "Удаляю пользователя: $username"
            samba-tool user delete "$username"
        fi
    done < <(tail -n +2 "$CSV_PATH")
    echo "✅ Все пользователи из CSV удалены"
}

# Функция импорта
import_users() {
    echo "🔄 Начинаю импорт пользователей..."
    while IFS="$SEPARATOR" read -r first_name last_name role phone ou street zip city country password
    do
        username=$(echo "${first_name:0:1}${last_name}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alpha:]')
        
        echo "➡️ Обработка: $username ($first_name $last_name)"
        
        # Создание пользователя
        if ! samba-tool user create "$username" "$password" \
            --given-name="$first_name" \
            --surname="$last_name" \
            --mail-address="$username@$DOMAIN"; then
            echo "❌ Ошибка создания $username"
            continue
        fi

        # Проверка пароля
        if ! smbclient -U "$username%$password" //localhost/netlogon -c 'exit' &>/dev/null; then
            echo "🛑 Пароль не работает, сбрасываю..."
            samba-tool user setpassword "$username" --newpassword="$password"
        fi

        # Группы
        if ! samba-tool group list | grep -q "^${role}$"; then
            samba-tool group add "$role"
        fi
        samba-tool group addmembers "$role" "$username"

        samba-tool user setexpiry "$username" --noexpiry
        
        echo "✅ Успешно: $username"
    done < <(tail -n +2 "$CSV_PATH")
}

# Главный процесс
delete_existing_users
import_users

echo "🎉 Все операции завершены!"