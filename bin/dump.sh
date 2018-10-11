#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

KEY="$(dirname "$(readlink -f "$0")")/key"

_enc() {
	openssl enc -aes-256-cbc -md sha256 -salt "$@"
}

dump() {
	local dbtype host username password db path enc port
	dbtype="$1"
	host="$2"
	username="$3"
	password="$4"
	db="$5"
	path="$6"
	enc="$7"

	port="$(dbport "$dbtype")"

	if [[ $# -gt 7 ]]; then
		tunnel "$host" "$8" "$port"
		host="127.0.0.1"
	fi

	case $dbtype in
		mysql)
			mysqldump --opt -h "$host" -u "$username" -p"$password" "$db"
			;;
		mongo)
			mongodump --quiet --host="$host" --username="$username" --password="$password" --db="$db" --archive
			;;
		postgres)
			PGPASSWORD="$password" pg_dump -h "$host" -U "$username" --no-password "$db"
			;;
	esac \
		| gzip - \
		| _enc -k "$enc" -out "$path"
}


restore() {
	local dbtype host username password db path enc port
	dbtype="$1"
	host="$2"
	username="$3"
	password="$4"
	db="$5"
	path="$6"
	enc="$7"

	port="$(dbport "$dbtype")"

	if [[ $# -gt 7 ]]; then
		tunnel "$host" "$8" "$port"
		host="127.0.0.1"
	fi

	_enc -d -k "$enc" -in "$path" \
	| gunzip - \
	| case $dbtype in
		mysql)
			mysql -h "$host" -u "$username" -p"$password" "$db"
			;;
		mongo)
			mongorestore --quiet --host="$host" --username="$username" --password="$password" --db="$db" --archive
			;;
		postgres)
			PGPASSWORD="$password" psql -h "$host" -U "$username" --no-password "$db"
			;;
	esac
}


dbport() {
	local dbtype
	dbtype="$1"

	case $dbtype in
		mysql)
			echo "3306"
			;;
		mongo)
			echo "27017"
			;;
		postgres)
			echo "5432"
			;;
		*)
			echo "Unknown database type '$1'."
			exit 1
			;;
	esac
}


tunnel() {
	local host tunnel port pid
	host="$1"
	tunnel="$2"
	port="$3"
	ssh -o StrictHostKeyChecking=false -i "$KEY" -N -L "$port":"$host":"$port" "$tunnel" &
	pid="$!"
	# Close tunnel on exit and preserve succes/failure
	trap "kill -SIGKILL '$pid'" 0
	trap "kill -SIGKILL '$pid'; exit 1" 1 2 15
	# Wait for ssh connection
	sleep 10
}

"$1" "${@:2}"

# vim:set noet:
