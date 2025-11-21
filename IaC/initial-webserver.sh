#!/bin/bash
# Autor: Deon Ramadani
# Datum: 2025-11-21
# Erklärung: Dieses Skript installiert und konfiguriert einen Apache-Webserver
#            mit PHP 8.2 und Nextcloud.

# 1) Aktualisierung der Paketliste
sudo apt-get update

# 2) Tool für add-apt-repository installieren
sudo apt-get install -y software-properties-common

# 3) PHP 8.2 Repository hinzufügen und Paketliste aktualisieren
sudo add-apt-repository ppa:ondrej/php -y
sudo apt-get update

# 4) Installation des Apache-Webservers
sudo apt-get install -y apache2

# 5) PHP 8.2 und benötigte Module installieren
sudo apt-get install -y \
  php8.2 \
  libapache2-mod-php8.2 \
  php8.2-gd \
  php8.2-json \
  php8.2-xml \
  php8.2-mbstring \
  php8.2-curl \
  php8.2-zip \
  php8.2-mysql \
  php8.2-intl \
  php8.2-bcmath \
  php8.2-gmp

# 6) Apache starten und beim Systemstart aktivieren
sudo systemctl start apache2
sudo systemctl enable apache2

# 7) Nextcloud herunterladen und entpacken
cd /tmp
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip
sudo apt-get install -y unzip
sudo unzip nextcloud.zip -d /var/www/

# 8) Rechte für den Webserver-Benutzer setzen
sudo chown -R www-data:www-data /var/www/nextcloud
sudo chmod -R 755 /var/www/nextcloud

# 9) Apache so konfigurieren, dass Nextcloud die Startseite ist
sudo sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/nextcloud|' /etc/apache2/sites-available/000-default.conf
sudo sed -i 's|/var/www/html|/var/www/nextcloud|g' /etc/apache2/sites-available/000-default.conf

# 10) Rewrite-Modul aktivieren (wird von Nextcloud benötigt)
sudo a2enmod rewrite

# 11) Apache neu starten, damit alle Änderungen aktiv werden
sudo systemctl restart apache2