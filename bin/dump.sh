#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

KEY="$(dirname "$(readlink -f "$0")")/key"

_enc() {
	openssl enc -aes-256-cbc -md sha256 -salt "$@"
}

dump_ravendb() {
	local url cert key database collections path enc options
	url="$1"
	cert="$2"
	key="$3"
	database="$4"
	collections="$5"
	path="$6"
	enc="$7"

	options="$(printf 'DownloadOptions={"Collections":%s,"IncludeExpired":true,"RemoveAnalyzers":false,"OperateOnTypes":"DatabaseRecord,Documents,Conflicts,Indexes,Identities,CompareExchange,CounterGroups,Attachments,Subscriptions","MaxStepsForTransformScript":10000}' "$collections")"

	curl -sfk "$url/databases/$database/smuggler/export" --cert "$cert" --key "$key" --data-binary "$options" \
		| _enc -k "$enc" -out "$path"
}

dump_other() {
	local dbtype host username password db path enc collections tunnel port
	dbtype="$1"
	host="$2"
	username="$3"
	password="$4"
	db="$5"
	path="$6"
	enc="$7"
	collections="${8:-}"
	tunnel="${9:-}"

	port="$(dbport "$dbtype")"

	if [[ -n $tunnel ]]; then
		tunnel "$host" "$tunnel" "$port"
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

restore_other() {
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
			mongorestore -vvv --host="$host" --username="$username" --password="$password" --db="$db" --archive --nsFrom='$prefix$.$suffix$' --nsTo="$db.\$suffix\$" --nsInclude="*"
			;;
		postgres)
			PGPASSWORD="$password" psql -h "$host" -U "$username" --no-password "$db"
			;;
	esac
}

restore_ravendb() {
	local url cert key database path enc options
	url="$1"
	cert="$2"
	key="$3"
	database="$4"
	path="$5"
	enc="$6"

	options='importOptions={"IncludeExpired":true,"RemoveAnalyzers":false,"OperateOnTypes":"DatabaseRecord,Documents,Conflicts,Indexes,RevisionDocuments,Identities,CompareExchange,Counters,Attachments,Subscriptions"}'

	_enc -d -k "$enc" -in "$path" \
	| curl -fk "$url/databases/$database/smuggler/import" --cert "$cert" --key "$key" -F "$options" -F "file=@-"
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
