#!/bin/bash
# Autor: Deon Ramadani
# Datum: 2025-11-21
# Erklärung: Dieses Skript installiert und konfiguriert einen Apache-Webserver
#            mit PHP 8.2 und Nextcloud.

set -e

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
# Da man sie nicht alle in einem Befehl installieren kann, werden sie einzeln installiert

sudo apt-get install -y php8.2

sudo apt-get install -y libapache2-mod-php8.2

sudo apt-get install -y php8.2-gd

sudo apt-get install -y php8.2-xml

sudo apt-get install -y php8.2-mbstring

sudo apt-get install -y php8.2-curl

sudo apt-get install -y php8.2-zip

sudo apt-get install -y php8.2-mysql

sudo apt-get install -y php8.2-intl

sudo apt-get install -y php8.2-bcmath

sudo apt-get install -y php8.2-gmp

# 6) Apache starten und beim Systemstart aktivieren
sudo systemctl start apache2
sudo systemctl enable apache2

# wget installieren
sudo apt-get install -y wget unzip

# 7) Nextcloud herunterladen und entpacken
cd /tmp
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip
sudo unzip nextcloud.zip -d /var/www/

# 8) Rechte für den Webserver-Benutzer setzen
sudo chown -R www-data:www-data /var/www/nextcloud
sudo chmod -R 755 /var/www/nextcloud

# 9) Apache so konfigurieren, dass Nextcloud die Startseite ist

IP_WEB_SERVER="$(curl -s https://ifconfig.me)"

cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerAdmin xxxx
    DocumentRoot /var/www/nextcloud/
    ServerName $IP_WEB_SERVER
<Directory /var/www/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
<IfModule mod_dav.c>
            Dav off
</IfModule>
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
</Directory>
    ErrorLog /var/log/apache2/nextcloud_error.log
    CustomLog /var/log/apache2/nextcloud_access.log combined
</VirtualHost>
EOF
 
# Apache Site aktivieren und Standardseite deaktivieren
a2dissite 000-default.conf
a2ensite nextcloud.conf
systemctl reload apache2

# sudo sed -i 's|DocumentRoot .*|DocumentRoot /var/www/nextcloud|' /etc/apache2/sites-available/000-default.conf
# sudo sed -i 's|/var/www/html|/var/www/nextcloud|g' /etc/apache2/sites-available/000-default.conf



# 10) Rewrite-Modul aktivieren (wird von Nextcloud benötigt)
sudo a2enmod rewrite

# 11) AllowOverride aktivieren, damit Nextclouds .htaccess/rewrites greifen
sudo sed -i '/DocumentRoot \/var\/www\/nextcloud/a \<Directory /var/www/nextcloud/>\n\tAllowOverride All\n</Directory>' /etc/apache2/sites-available/000-default.conf

# 11) Apache neu starten, damit alle Änderungen aktiv werden
sudo systemctl restart apache2