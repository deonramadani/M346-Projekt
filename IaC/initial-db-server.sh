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
sed -i -E "s/^[#[:space:]]*bind-address[[:space:]]*=.*$/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql

# 7) Interne IP-Adresse des Datenbankservers ermitteln
DB_IP=$(hostname -I | awk '{print $1}')

# 8) Verbindungsoptionen für Nextcloud ausgeben
echo "Datenbank-Host: $DB_IP"
echo "Datenbank-Name: nextcloud"
echo "Datenbank-Benutzer: nextcloud"
echo "Datenbank-Passwort: nextcloud-pass"