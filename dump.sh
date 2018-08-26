#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

KEY="$(dirname "$(readlink -f "$0")")/key"

main() {
	local dbtype host username password db path enc port
	dbtype="$1"
	host="$2"
	username="$3"
	password="$4"
	db="$5"
	path="$6"
	enc="$7"

	case $dbtype in
		mysql)
			port="3306"
			;;
		mongo)
			port="27017"
			;;
		postgres)
			port="5432"
			;;
		*)
			echo "Unknown database type '$1'."
			exit 1
			;;
	esac

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
		| openssl enc -aes-256-cbc -md sha256 -salt -k "$enc" -out "$path"
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

main "$@"

# vim:set noet:
