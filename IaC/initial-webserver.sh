#!/bin/bash -xe

export DEBIAN_FRONTEND=noninteractive

# 1) Apache + PHP installieren
sudo apt-get update -y

sudo apt-get install -y \
  apache2 wget unzip \
  php php-cli libapache2-mod-php \
  php-gd php-mbstring php-xml php-zip \
  php-curl php-intl php-bcmath php-gmp php-mysql

# 2) Apache-Module aktivieren
sudo a2enmod rewrite headers env dir mime ssl

sudo systemctl enable apache2
sudo systemctl start apache2

# 3) Nextcloud herunterladen
NEXTCLOUD_VERSION="${NEXTCLOUD_VERSION:-latest}"

cd /tmp
sudo rm -rf nextcloud nextcloud.zip

wget -q "https://download.nextcloud.com/server/releases/${NEXTCLOUD_VERSION}.zip" -O nextcloud.zip
unzip nextcloud.zip
sudo rm nextcloud.zip

# 4) Nextcloud nach /var/www/nextcloud verschieben
sudo rm -rf /var/www/nextcloud
sudo mv nextcloud /var/www/nextcloud

# 5) Rechte setzen
sudo chown -R www-data:www-data /var/www/nextcloud
sudo find /var/www/nextcloud/ -type d -exec chmod 750 {} \;
sudo find /var/www/nextcloud/ -type f -exec chmod 640 {} \;

# 6) Apache-VHost so ändern, dass direkt Nextcloud die Startseite ist
sudo sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/nextcloud|' \
  /etc/apache2/sites-available/000-default.conf

# Falls noch eine Standardindex-Datei existiert, löschen
sudo rm -f /var/www/html/index.html

# 7) Directory-Konfiguration für Nextcloud
cat << 'EOF' | sudo tee /etc/apache2/conf-available/nextcloud.conf
<Directory /var/www/nextcloud>
    Require all granted
    AllowOverride All
    Options FollowSymLinks MultiViews
</Directory>
EOF

sudo a2enconf nextcloud

# 8) Apache neu laden
sudo systemctl reload apache2
