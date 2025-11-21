#!/bin/bash
# Autor: Deon Ramadani
# Datum: 2025-11-21
# Erklärung: Dieses Skript installiert und konfiguriert einen MySQL-Datenbankserver

# 1) Aktualisierung der Paketliste
sudo apt-get update

# 2) Installation des MySQL-Datenbankservers
sudo apt-get install -y mysql-server

# 3) Starten und Aktivieren des MySQL-Datenbankservers
sudo systemctl start mysql

# 4) Sicherstellen, dass der MySQL-Datenbankserver beim Systemstart automatisch gestartet wird
sudo systemctl enable mysql

# 5) Nextcloud-Datenbank und Benutzer anlegen
sudo mysql -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
sudo mysql -e "CREATE USER 'nextcloud'@'%' IDENTIFIED BY 'nextcloud-pass';"
sudo mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'%';"
sudo mysql -e "FLUSH PRIVILEGES;"

# 6) Remote-Zugriff erlauben (bind-address anpassen)
sudo sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql
