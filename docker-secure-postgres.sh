#!/usr/bin/env bash
# title          :Secure Postgress Docker Container for Development
# description    :This is a script that I created to expedite the 
#                 creation of a secure docker container during the 
#                 development of a Django application
# file_nam       :docker-secure-postgres.sh
# author         :Adrian Puente Z.
# date           :20200315
# version        :1.0
# bash_version   :GNU bash, version 5.0.3(1)-release (x86_64-pc-linux-gnu)
#==================================================================

set -euo pipefail

[ $(id -u) -ne 0 ] && echo "Only root can do that! sudoing..."
if [ "${EUID}" != 0 ]; then sudo $(which ${0}) ${@}; exit; fi

## Configure these variables if needed
APPDBHOSTNAME="localhost"
APPDBSRVPORT="5432"
APPUSRNAME="appusr"
APPDBNAME="appdb"
APPDBPASSWD=$(python -c "import random ; print(''.join([random.SystemRandom().choice('abcdefghijklmnopqrstuvwxyz0123456789%^&*(-_+)') for i in range(25)]))")
PGPASSWORD=$(python -c "import random ; print(''.join([random.SystemRandom().choice('abcdefghijklmnopqrstuvwxyz0123456789%^&*(-_+)') for i in range(25)]))")
DOCKERSRVNAME="postgres-securesrv"
SQLFILE=$(mktemp)
True=0
False=1

# Destroys any old docker container with the same name.
if docker ps -a | grep ${DOCKERSRVNAME} >/dev/null 2>&1 
then 
	echo "Deleting existing ${DOCKERSRVNAME} container."
	docker stop ${DOCKERSRVNAME} > /dev/null 2>&1
	docker rm ${DOCKERSRVNAME} > /dev/null 2>&1
fi

# You can comment this part and add your own certificates. Be sure
# to copy them in this directory and to name them accordingly.
openssl req -new -text -passout pass:abcd -subj /CN=${APPDBHOSTNAME} -out server.req -keyout privkey.pem
openssl rsa -in privkey.pem -passin pass:abcd -out server.key
openssl req -x509 -in server.req -text -key server.key -out server.crt
## Setting the right permissions for the postgress user
chmod 600 server.key
chown 999:999 server.key

docker run -d --name ${DOCKERSRVNAME} \
		   -v "${PWD}/server.crt:/var/lib/postgresql/server.crt:ro" \
		   -v "${PWD}/server.key:/var/lib/postgresql/server.key:ro" \
		   -e POSTGRES_PASSWORD=${PGPASSWORD} \
		   -p ${APPDBSRVPORT}:${APPDBSRVPORT} \
		   postgres \
		   -c ssl=on \
		   -c ssl_cert_file=/var/lib/postgresql/server.crt \
		   -c ssl_key_file=/var/lib/postgresql/server.key 

echo "Waiting for the container to initialize."
FAILED=${True}
# Waits up to 30 seconds for the container to initialize.
for ((i=0 ; i<6 ; i++))
do
	sleep 5
	if docker ps | grep ${DOCKERSRVNAME} > /dev/null 2>&1 
	then
		if 	PGPASSWORD="${PGPASSWORD}" \
			pg_isready -h ${APPDBHOSTNAME} \
					   -p ${APPDBSRVPORT} \
					   -U postgres
		then
			FAILED=${False}
			break
		fi
	fi
done

if [ ${FAILED} -eq ${True} ]
then
	echo "Container execution failed, showing the logs"
	docker logs ${DOCKERSRVNAME}
	exit 1
fi

echo "Creating sample database."
cat > ${SQLFILE} << _END
CREATE DATABASE ${APPDBNAME};
CREATE USER ${APPUSRNAME} WITH PASSWORD '${APPDBPASSWD}';
ALTER ROLE ${APPUSRNAME} SET client_encoding TO 'utf8';
ALTER ROLE ${APPUSRNAME} SET default_transaction_isolation TO 'read committed';
ALTER ROLE ${APPUSRNAME} SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE ${APPDBNAME} TO ${APPUSRNAME};
_END

# Creating the sample database.
PGPASSWORD="${PGPASSWORD}" psql -h ${APPDBHOSTNAME} -U postgres -f ${SQLFILE}
rm -fr ${SQLFILE}

echo "Sample database created successfully"
echo -en "Save both strings below in your .env file and restart the pipenv environment.\n\n"
echo "DATABASE_URL=\"postgres://${APPUSRNAME}:${APPDBPASSWD}@${APPDBHOSTNAME}:${APPDBSRVPORT}/${APPDBNAME}\""
echo "PGPASSWORD=\"${PGPASSWORD}\""
exit 0
