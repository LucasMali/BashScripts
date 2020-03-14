#!/bin/bash

install_magento () {
    FOLDER=magento
    if [ ! -z "$1" ]; then
        FOLDER=$1
    fi
    cd ${HOME}/Sites/${FOLDER}/
    composer create-project --repository-url=https://repo.magento.com/ magento/project-enterprise-edition .
    import_db
    install_script magento.test admin magento magento
}

install_script () {
     bin/magento setup:install \
    --backend-frontname=$2 \
    --amqp-host=127.0.0.1 \
    --amqp-port=5672 \
    --amqp-user=guest \
    --amqp-password=guest \
    --db-host=127.0.0.1 \
    --db-name=$3 \
    --db-user=$4 \
    --db-password= \
    --http-cache-hosts=varnish:80 \
    --session-save=redis \
    --session-save-redis-host=127.0.0.1 \
    --session-save-redis-port=6379 \
    --session-save-redis-db=2 \
    --session-save-redis-max-concurrency=20 \
    --cache-backend=redis \
    --cache-backend-redis-server=127.0.0.1 \
    --cache-backend-redis-db=0 \
    --cache-backend-redis-port=6379 \
    --page-cache=redis \
    --page-cache-redis-server=127.0.0.1 \
    --page-cache-redis-db=1 \
    --page-cache-redis-port=6379

    php bin/magento app:config:import

    php bin/magento config:set --lock-env web/unsecure/base_url "http://${1}/"
    php bin/magento config:set --lock-env web/secure/base_url "http://${1}/"

    php bin/magento config:set --lock-env web/secure/use_in_frontend 0
    php bin/magento config:set --lock-env web/secure/use_in_adminhtml 0 
    php bin/magento config:set --lock-env web/seo/use_rewrites 0

    php bin/magento config:set --lock-env system/full_page_cache/caching_application 2 
    php bin/magento config:set --lock-env system/full_page_cache/ttl 604800

    php bin/magento config:set --lock-env catalog/search/engine elasticsearch6 
    php bin/magento config:set --lock-env catalog/search/enable_eav_indexer 1 
    php bin/magento config:set --lock-env catalog/search/elasticsearch6_server_hostname 127.0.0.1 
    php bin/magento config:set --lock-env catalog/search/elasticsearch6_server_port 9200 
    php bin/magento config:set --lock-env catalog/search/elasticsearch6_index_prefix magento2 
    php bin/magento config:set --lock-env catalog/search/elasticsearch6_enable_auth 0 
    php bin/magento config:set --lock-env catalog/search/elasticsearch6_server_timeout 15
    php bin/magento config:set --lock-env dev/static/sign 0

    php bin/magento app:config:import
    php bin/magento s:up

    php bin/magento config:set  --lock-env admin/security/password_is_forced 0;
    php bin/magento config:set  --lock-env msp_securitysuite_recaptcha/backend/enabled  0;
    php bin/magento config:set  --lock-env web/secure/use_in_adminhtml 0;
    php bin/magento msp:security:tfa:disable
    php bin/magento deploy:mode:set developer 
    php bin/magento cache:disable block_html full_page
    php bin/magento indexer:reindex 
    php bin/magento cache:flush

    ADMINPASS="magento123"
    ADMINUSER="magento"

    bin/magento admin:user:create \
        --admin-password="${ADMINPASS}" \
        --admin-user="${ADMINUSER}" \
        --admin-firstname="Local" \
        --admin-lastname="Admin" \
        --admin-email="${ADMINUSER}@example.com";
}

# For existing sites
import_db () {
    DATABASE=magento
    if [ ! -z "$1" ]; then
        DATABASE=$1
    fi
    FILE=${HOME}/Dumps/$(ls -Art ${HOME}/Dumps/*.sql | tail -n 1 | xargs -n 1 basename);
    if [ ! -f "$FILE" ]; then
        echo "no file $FILE"
        return
    fi

    pv $FILE | mysql $DATABASE;
}

install_magento
