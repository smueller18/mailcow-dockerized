#!/bin/sh

if [ -d /app/installer ]; then
  if [ ! -z "$DBNAME" ] && [ ! -z "$DBUSER" ] && [ ! -z "$DBPASS" ]; then
    echo "Initialize mysql database"
    bin/initdb.sh --dir "/app/SQL" > /tmp/stdout 2> /tmp/stderr
    exitcode=$?
    if [ "$exitcode" != 0 ]; then
      if grep -q "already exists (SQL Query: CREATE TABLE" /tmp/stderr; then
        echo "Database is already initialized"
      else
        echo "Initialization failed"
        cat /tmp/stdout /tmp/stderr
        exit $exitcode
      fi
    else
      cat /tmp/stdout
    fi
    rm -rf /app/installer
    rm -f /tmp/stdout /tmp/stderr
    if [ -f "/app/logs/sql" ]; then
      chown www-data:www-data /app/logs/sql
    fi
  fi
fi

exec "$@"
