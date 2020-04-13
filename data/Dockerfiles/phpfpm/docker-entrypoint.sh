#!/bin/bash

set -x

if [ ! -d /web ]; then
  (cd /tmp && curl -sSL https://github.com/smueller18/archive/smueller18.tar.gz | tar xvzf -)
  mv /tmp/mailcow-dockerized-smueller18/data/web/ /
  rm -rf /tmp/mailcow-dockerized-smueller18
fi
sed -i 's#/var/run/mysqld/mysqld.sock##g' /web/inc/vars.inc.php
find /web -name "*.php" -exec sed -i 's#":unix_socket=" . $database_sock#":host=mysql"#g' {} \;


if [ ! -f /usr/local/bin/jq ]; then
  curl -sSL https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -o /usr/local/bin/jq
  chmod +x /usr/local/bin/jq
fi
RAINLOOP_LATEST_RELEASE=https://api.github.com/repos/rainloop/rainloop-webmail/releases/latest
RAINLOOP_LATEST_VERSION=$(curl -sSL $RAINLOOP_LATEST_RELEASE | jq -r .name)

if [ ! -f /rainloop/data/VERSION ] || [ "$(cat /rainloop/data/VERSION)" != "$RAINLOOP_LATEST_VERSION" ] || [ ! -d /rainloop/rainloop ]; then
  echo "Updating Rainloop to version $RAINLOOP_LATEST_VERSION ..."
  mkdir -p /rainloop
  DOWNLOAD_URL=$(curl -sSL $RAINLOOP_LATEST_RELEASE \
    | jq -r '.assets[] | select( .name | match ( "^rainloop-community-[0-9]*.[0-9]*.[0-9]*.zip$" ) ) | .browser_download_url')
  curl -sSL $DOWNLOAD_URL -o /tmp/rainloop.zip
  rm -rf /rainloop/rainloop
  unzip -qo /tmp/rainloop.zip -d /rainloop
  chown -R www-data:www-data /rainloop
  find /rainloop -type d -exec chmod 755 {} \;
  find /rainloop -type f -exec chmod 644 {} \;
  rm -rf /tmp/rainloop.zip
  echo "Finished updating Rainloop"
else
  echo "Rainloop is up to date"
fi

echo "Creating Rainloop config"
rm -rf /rainloop/data/_data_/_default_/domains/{disabled,gmail.com.ini,outlook.com.ini,qq.com.ini,yahoo.com.ini}

envsubst < /rainloop-config/application.ini.template \
         > /rainloop/data/_data_/_default_/configs/application.ini

envsubst < /rainloop-config/domain.ini.template \
         > /rainloop/data/_data_/_default_/domains/${MAILCOW_DOMAINNAME}.ini

for alias in $RAINLOOP_ALIASES; do
  echo $MAILCOW_DOMAINNAME > /rainloop/data/_data_/_default_/domains/$alias.alias.ini
done


function array_by_comma { local IFS=","; echo "$*"; }

# Wait for containers
while ! mysqladmin status -h${DBHOST} -u${DBUSER} -p${DBPASS} --silent; do
  echo "Waiting for SQL..."
  sleep 2
done

# Do not attempt to write to slave
if [[ ! -z ${REDIS_SLAVEOF_IP} ]]; then
  REDIS_CMDLINE="redis-cli -h ${REDIS_SLAVEOF_IP} -p ${REDIS_SLAVEOF_PORT}"
else
  REDIS_CMDLINE="redis-cli -h redis -p 6379"
fi

until [[ $(${REDIS_CMDLINE} PING) == "PONG" ]]; do
  echo "Waiting for Redis..."
  sleep 2
done

if [[ "${MASTER}" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
  echo "We are master, preparing..."

  # Set max age of q items - if unset
  if [[ -z $(${REDIS_CMDLINE} --raw GET Q_MAX_AGE) ]]; then
    ${REDIS_CMDLINE} --raw SET Q_MAX_AGE 365
  fi

  # Trigger db init
  echo "Running DB init..."
  php -c /usr/local/etc/php -f /web/inc/init_db.inc.php

  # Recreating domain map
  echo "Rebuilding domain map in Redis..."
  declare -a DOMAIN_ARR
    ${REDIS_CMDLINE} DEL DOMAIN_MAP > /dev/null
  while read line
  do
    DOMAIN_ARR+=("$line")
  done < <(mysql -h${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} -e "SELECT domain FROM domain" -Bs)
  while read line
  do
    DOMAIN_ARR+=("$line")
  done < <(mysql -h${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} -e "SELECT alias_domain FROM alias_domain" -Bs)
  if [[ ! -z ${DOMAIN_ARR} ]]; then
  for domain in "${DOMAIN_ARR[@]}"; do
    ${REDIS_CMDLINE} HSET DOMAIN_MAP ${domain} 1 > /dev/null
  done
  fi

  # Set API options if env vars are not empty
  if [[ ${API_ALLOW_FROM} != "invalid" ]] && [[ ! -z ${API_ALLOW_FROM} ]]; then
    IFS=',' read -r -a API_ALLOW_FROM_ARR <<< "${API_ALLOW_FROM}"
    declare -a VALIDATED_API_ALLOW_FROM_ARR
    REGEX_IP6='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/([0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8]))?$'
    REGEX_IP4='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/([0-9]|[1-2][0-9]|3[0-2]))?$'
    for IP in "${API_ALLOW_FROM_ARR[@]}"; do
      if [[ ${IP} =~ ${REGEX_IP6} ]] || [[ ${IP} =~ ${REGEX_IP4} ]]; then
        VALIDATED_API_ALLOW_FROM_ARR+=("${IP}")
      fi
    done
    VALIDATED_IPS=$(array_by_comma ${VALIDATED_API_ALLOW_FROM_ARR[*]})
    if [[ ! -z ${VALIDATED_IPS} ]]; then
      if [[ ${API_KEY} != "invalid" ]] && [[ ! -z ${API_KEY} ]]; then
        mysql --socket=/var/run/mysqld/mysqld.sock -u ${DBUSER} -p${DBPASS} ${DBNAME} << EOF
DELETE FROM api WHERE access = 'rw';
INSERT INTO api (api_key, active, allow_from, access) VALUES ("${API_KEY}", "1", "${VALIDATED_IPS}", "rw");
EOF
      fi
      if [[ ${API_KEY_READ_ONLY} != "invalid" ]] && [[ ! -z ${API_KEY_READ_ONLY} ]]; then
        mysql -h${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} << EOF
DELETE FROM api WHERE access = 'ro';
INSERT INTO api (api_key, active, allow_from, access) VALUES ("${API_KEY_READ_ONLY}", "1", "${VALIDATED_IPS}", "ro");
EOF
      fi
    fi
  fi

  # Create events (master only, STATUS for event on slave will be SLAVESIDE_DISABLED)
  mysql -h${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} << EOF
DROP EVENT IF EXISTS clean_spamalias;
DELIMITER //
CREATE EVENT clean_spamalias
ON SCHEDULE EVERY 1 DAY DO
BEGIN
  DELETE FROM spamalias WHERE validity < UNIX_TIMESTAMP();
END;
//
DELIMITER ;
DROP EVENT IF EXISTS clean_oauth2;
DELIMITER //
CREATE EVENT clean_oauth2
ON SCHEDULE EVERY 1 DAY DO
BEGIN
  DELETE FROM oauth_refresh_tokens WHERE expires < NOW();
  DELETE FROM oauth_access_tokens WHERE expires < NOW();
  DELETE FROM oauth_authorization_codes WHERE expires < NOW();
END;
//
DELIMITER ;
EOF
fi

# Create dummy for custom overrides of mailcow style
[[ ! -f /web/css/build/0081-custom-mailcow.css ]] && echo '/* Autogenerated by mailcow */' > /web/css/build/0081-custom-mailcow.css

# Fix permissions for global filters
chown -R 82:82 /global_sieve/*

# Run hooks
for file in /hooks/*; do
  if [ -x "${file}" ]; then
    echo "Running hook ${file}"
    "${file}"
  fi
done

exec "$@"
