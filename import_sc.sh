#!/bin/bash
csv_file="/opt/users.csv"
while IFS=";" read -r firstName lastName role phone ou street zip
        if [ "$firstName" == "First Name" ]; then
                continue
        fi
        username="${firstName,,}.${lastName,,}"
        sudo samba-tool user add "$username" P@ssw0rd1
done < "$csv_file"
