#!/bin/bash

# Проверка наличия файла
if [[ $# -eq 0 ]]; then
    echo "Использование: $0 путь_к_csv_файлу"
    exit 1
fi

CSV_FILE="$1"
SEPARATOR=";"  # Укажите ваш разделитель (; или ,)
PASSWORD="P@ssw0rd1"

# Проверка доступности samba-tool
if ! command -v samba-tool &> /dev/null; then
    echo "Ошибка: samba-tool не найден!"
    exit 1
fi

echo "🔄 Начинаю сброс паролей для пользователей из файла $CSV_FILE"

# Основной цикл обработки
while IFS="$SEPARATOR" read -r first_name last_name _ _ _ _ _ _ _ _
do
    # Генерация логина (первая буква имени + фамилия в нижнем регистре)
    username=$(echo "${first_name:0:1}${last_name}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alpha:]')
    
    # Проверка существования пользователя
    if samba-tool user list | grep -q "^${username}$"; then
        echo "🔧 Обновляю пароль для: $username"
        if samba-tool user setpassword "$username" --newpassword="$PASSWORD"; then
            echo "✅ Пароль для $username успешно изменён"
        else
            echo "❌ Ошибка при смене пароля для $username"
        fi
    else
        echo "⚠️ Пользователь $username не существует, пропускаю"
    fi
done < <(tail -n +2 "$CSV_FILE")  # Пропускаем заголовок

echo "🎉 Все операции завершены!"