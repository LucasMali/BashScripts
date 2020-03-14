#!/bin/bash
# Author Lucas Maliszewski
# March 13 2020
# Simple Debian/Ubuntu script to setup a LAMP stack for Magento 2
# NOTE: This should NOT be used for production enviornments, local dev only!
# Resources: 
#   https://askubuntu.com/questions/1184367/how-to-install-php7.2-in-ubuntu-19-10
#   https://computingforgeeks.com/install-elasticsearch-on-ubuntu/

update () {
    sudo apt update; sudo apt upgrade -y
}

init () {
    sudo apt-get install composer curl wget vim git pv -y
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    git config --global core.fileMode false
    sudo apt install zsh -y
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended    
    echo "

# Switch to ZSH shell
if test -t 1; then
exec zsh
fi
" >> ${HOME}/.bashrc
}

install_webserver () {
    sudo apt install apache2 -y;
    sudo systemctl enable apache2;
    sudo a2enmod rewrite;
    sudo systemctl restart apache2;
}

install_php () {
    sudo add-apt-repository ppa:ondrej/php -y
    update
    P_VER=php7.2
    sudo apt-get install $P_VER libapache2-mod-$P_VER $P_VER-{cli,intl,xml,common,gd,mysql,curl,xsl,mbstring,zip,bcmath,soap,fpm} php-xdebug -y
    sudo update-alternatives --set php /usr/bin/${P_VER}
    sudo a2enmod $P_VER
    php -v
}

install_database () {
    DB=mariadb
    sudo apt-get install $DB-{server,client} -y
    sudo systemctl enable mysql;
}

install_elasticsearch () {
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
    sudo apt-get -y install apt-transport-https
    echo "deb https://artifacts.elastic.co/packages/6.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-6.x.list
    update
    sudo apt-get -y install apt-transport-https openjdk-8-jre-headless
    sudo apt-get -y install elasticsearch
    sudo systemctl enable elasticsearch
    sudo systemctl start elasticsearch
}

install_cache () {
    sudo apt-get install redis -y
}

install_amqp () {
    sudo apt-get install rabbitmq-server -y
}

edit_php_config () {
    PHP_INI=$(php -i | grep -Po '(\/.*php\.ini)');
    FPM_INI=$(echo "${PHP_INI}" | sed -r 's/cli/fpm/g');
    files=($PHP_INI $FPM_INI);
    for file in "${files[@]}"
    do
        if [ -f "$file" ]; then
            sudo sed -i 's/display_errors = Off/display_errors = On/g' ${file};
            sudo sed -i 's/memory_limit = .*/memory_limit = 4000M/g' ${file};
            sudo sed -i 's/;opcache.enable=1/opcache.enable=1/g' ${file};
            echo "$file";
            sudo cat $file | grep display_errors;
            sudo cat $file | grep memory_limit;
            sudo cat $file | grep opcache.enable;
        else
            echo "$file does not exists!"
        fi
    done
}

edit_apache_env () {
    #for now assume location
    ENVVARS=/etc/apache2/envvars
    values=('export APACHE_RUN_USER=' 'export APACHE_RUN_GROUP=')
    user=$(whoami)
    for value in "${values[@]}"
    do
        sudo sed -i "s/${value}.*/${value}${user}/g" ${ENVVARS};
        sudo cat $ENVVARS | grep "$value"
    done
}

add_databases_and_users () {
    sites=("$@")
    for SITE in "${sites[@]}"
    do
        SQL="DROP DATABASE IF EXISTS ${SITE};
        CREATE DATABASE ${SITE};
        DROP USER IF EXISTS ${SITE}@localhost;
        CREATE USER ${SITE}@localhost;
        GRANT ALL ON ${SITE}.* TO ${SITE}@localhost;
        FLUSH PRIVILEGES;"
        sudo mysql -u root -e"$SQL";
    done
    sudo mysql -u root -e"SHOW DATABASES;"
    sudo mysql -u root -e"SELECT User, Host FROM mysql.user;"
}

add_hosts () {
    sites=("$@")

    for SITE in "${sites[@]}"
    do
        if ! grep -Fxq "${SITE}.test" /etc/hosts
        then
            echo "
            127.0.0.1    ${SITE}.test" | sudo tee -a /etc/hosts;
        fi
    done

}

add_virtual_hosts () {
    sites=("$@")
    for SITE in "${sites[@]}"
    do
        echo "
<VirtualHost *:80>
    Servername $SITE.test
    ServerAlias www.$SITE.test *.$SITE.test
    DocumentRoot $HOME/Sites/$SITE
    ErrorLog ${APACHE_LOG_DIR}/${SITE}_error.log
    CustomLog ${APACHE_LOG_DIR}/${SITE}_access.log combined
    <Directory $HOME/Sites/$SITE>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
        Require all granted
    </Directory>
</VirtualHost>
" | sudo tee /etc/apache2/sites-available/$SITE.conf
    done
}

add_site_folders () {
    sites=("$@")
    for SITE in "${sites[@]}"
    do
        if [ ! -d "${HOME}/Sites/${SITE}" ]; then
            mkdir -p ${HOME}/Sites/${SITE}
        fi
    done
}

add_info_site () {
    echo "<?php

    phpinfo();
    " > ${HOME}/Sites/info/index.php
}

enable_virtual_hosts () {
    sites=("$@")
    for SITE in "${sites[@]}"
    do
        sudo ln -s /etc/apache2/sites-available/${SITE}.conf /etc/apache2/sites-enabled/
    done
    ls -ltra /etc/apache2/sites-enabled/
    sudo systemctl restart apache2;

}


DEBIAN_FRONTEND=noninteractive
sites=(magento info)

update
init

install_webserver
install_php
install_database
install_elasticsearch
install_cache
install_amqp

edit_php_config
edit_apache_env

add_databases_and_users "${sites[@]}"
add_hosts "${sites[@]}"
add_virtual_hosts "${sites[@]}"
add_site_folders "${sites[@]}"
add_info_site
enable_virtual_hosts "${sites[@]}"
