#!/usr/bin/env bash
# Integration tests for the full dumptruck cycle. Runs inside the dumptruck
# image so the shipped database clients and rclone are what gets exercised.
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

WORK=/work
STORAGE=/storage/backups
ENC="test-encryption-key-do-not-log"
MYSQL_PW="mysql-secret-pw-do-not-log"
PG_PW="pg-secret-pw-do-not-log"
PUSH_PW="push-secret-pw-do-not-log"
PUSH_PORT=9091
PUSHED="$WORK/pushed.log"

# A distinctive value seeded into both databases, used to prove the dump really
# contains the data and that the stored artefact is not plaintext.
CANARY="canary-6f2a1c-row"

failures=0

info() { printf '\n\033[1m=== %s\033[0m\n' "$*"; }
ok() { printf '  \033[32mok\033[0m %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }

assert() {
	local label="$1"
	shift
	if "$@"; then ok "$label"; else bad "$label"; fi
}

refute() {
	local label="$1"
	shift
	if "$@"; then bad "$label"; else ok "$label"; fi
}

mysql_do() { MYSQL_PWD="$MYSQL_PW" mariadb -h mysql -u backup shop -N -B -e "$1"; }
pg_do() { PGPASSWORD="$PG_PW" psql -h postgres -U backup -d shop -t -A -c "$1"; }

seed() {
	info "seeding databases"
	mysql_do "DROP TABLE IF EXISTS items;
		CREATE TABLE items (id INT PRIMARY KEY, label VARCHAR(64));
		INSERT INTO items VALUES (1, '$CANARY'), (2, 'second-row');"
	pg_do "DROP TABLE IF EXISTS items;
		CREATE TABLE items (id INT PRIMARY KEY, label VARCHAR(64));
		INSERT INTO items VALUES (1, '$CANARY'), (2, 'second-row');"
	ok "mysql rows: $(mysql_do 'SELECT COUNT(*) FROM items')"
	ok "postgres rows: $(pg_do 'SELECT COUNT(*) FROM items')"
}

write_config() {
	# keep=$1
	cat > "$WORK/config.json" <<EOF
{
  "encryption": "$ENC",
  "sources": [
    {
      "name": "mysql-shop", "dbtype": "mysql", "host": "mysql",
      "database": "shop", "username": "backup", "password": "$MYSQL_PW", "keep": $1
    },
    {
      "name": "pg-shop", "dbtype": "postgres", "host": "postgres",
      "database": "shop", "username": "backup", "password": "$PG_PW", "keep": $1
    }
  ],
  "storage": [
    { "type": "rclone", "remote": "store", "target": "$STORAGE" }
  ],
  "monitor": {
    "url": "http://127.0.0.1:$PUSH_PORT",
    "username": "push",
    "password": "$PUSH_PW",
    "labels": { "environment": "ci" }
  }
}
EOF
}

write_failing_config() {
	cat > "$WORK/broken.json" <<EOF
{
  "encryption": "$ENC",
  "sources": [
    {
      "name": "unreachable", "dbtype": "mysql", "host": "no-such-host.invalid",
      "database": "shop", "username": "backup", "password": "$MYSQL_PW", "keep": 2
    }
  ],
  "storage": [
    { "type": "rclone", "remote": "store", "target": "$STORAGE" }
  ],
  "monitor": {
    "url": "http://127.0.0.1:$PUSH_PORT",
    "username": "push",
    "password": "$PUSH_PW",
    "labels": { "environment": "ci" }
  }
}
EOF
}

stored() { find "$STORAGE" -name '*.enc' -type f | sort; }
stored_count() { stored | wc -l | tr -d ' '; }

main() {
	mkdir -p "$STORAGE"
	cd "$WORK"

	# rclone.py invokes `rclone --config rclone`, i.e. a config file in the CWD.
	printf '[store]\ntype = local\n' > "$WORK/rclone"

	PUSHGATEWAY_LOG="$PUSHED" python3 /test/pushgateway.py "$PUSH_PORT" &
	# Global, not local: the EXIT trap runs after main() has returned.
	gw_pid=$!
	trap 'kill "${gw_pid:-}" 2>/dev/null || true' EXIT
	for _ in $(seq 30); do
		curl -sf -o /dev/null "http://127.0.0.1:$PUSH_PORT" -d '' && break || sleep 0.2
	done

	seed
	write_config 2
	write_failing_config

	info "backup of both sources succeeds"
	if /app/dumptruck.py "$WORK/config.json" > "$WORK/backup.log" 2>&1; then
		ok "exit status 0"
	else
		bad "exit status $?"
	fi
	sed 's/^/  | /' "$WORK/backup.log"

	assert "two artefacts stored" test "$(stored_count)" -eq 2
	assert "mysql artefact present" bash -c "find $STORAGE -name '*.enc' | grep -q mysql-shop"
	assert "postgres artefact present" bash -c "find $STORAGE -name '*.enc' | grep -q pg-shop"

	info "stored artefacts are encrypted, not plaintext"
	local artefact
	for artefact in $(stored); do
		refute "$(basename "$artefact") does not contain the canary" grep -qa "$CANARY" "$artefact"
		assert "$(basename "$artefact") has openssl salt header" bash -c \
			"head -c8 '$artefact' | grep -qa Salted__"
	done

	info "secrets never appear in the log (regression test)"
	local secret
	for secret in "$ENC" "$MYSQL_PW" "$PG_PW" "$PUSH_PW"; do
		refute "log is free of ${secret:0:12}..." grep -qa "$secret" "$WORK/backup.log"
	done

	info "success metrics pushed with configured labels"
	assert "backup_status 1 for mysql-shop" grep -q \
		'instance/mysql-shop backup_status{.*environment="ci".*} 1' "$PUSHED"
	assert "backup_status 1 for pg-shop" grep -q \
		'instance/pg-shop backup_status{.*environment="ci".*} 1' "$PUSHED"
	assert "backup_time_seconds reported" grep -q 'backup_time_seconds{' "$PUSHED"
	assert "default labels present" grep -q 'database="shop"' "$PUSHED"

	info "restore rebuilds a dropped table"
	local mysql_dump pg_dump_file
	mysql_dump="$(basename "$(stored | grep mysql-shop)")"
	pg_dump_file="$(basename "$(stored | grep pg-shop)")"

	mysql_do "DROP TABLE items;"
	refute "mysql table is gone" mysql_do "SELECT 1 FROM items LIMIT 1;"
	/app/dumptruck.py "$WORK/config.json" mysql-shop "$mysql_dump" > "$WORK/restore-mysql.log" 2>&1 \
		|| bad "mysql restore exited non-zero"
	sed 's/^/  | /' "$WORK/restore-mysql.log"
	assert "mysql rows restored" test "$(mysql_do 'SELECT COUNT(*) FROM items')" = "2"
	assert "mysql canary restored" test "$(mysql_do "SELECT label FROM items WHERE id=1")" = "$CANARY"

	pg_do "DROP TABLE items;"
	/app/dumptruck.py "$WORK/config.json" pg-shop "$pg_dump_file" > "$WORK/restore-pg.log" 2>&1 \
		|| bad "postgres restore exited non-zero"
	sed 's/^/  | /' "$WORK/restore-pg.log"
	assert "postgres rows restored" test "$(pg_do 'SELECT COUNT(*) FROM items')" = "2"
	assert "postgres canary restored" test "$(pg_do 'SELECT label FROM items WHERE id=1')" = "$CANARY"

	info "retention deletes the oldest backups beyond keep"
	# Filenames carry a minute-resolution timestamp, so back-date synthetic
	# artefacts rather than trying to take three real backups in one minute.
	touch "$STORAGE/mysql-shop.20200101-0000.gz.enc" \
		"$STORAGE/mysql-shop.20200102-0000.gz.enc" \
		"$STORAGE/mysql-shop.20200103-0000.gz.enc"
	local before
	before="$(stored_count)"
	write_config 2
	/app/dumptruck.py "$WORK/config.json" mysql-shop > "$WORK/retention.log" 2>&1 \
		|| bad "retention run exited non-zero"
	sed 's/^/  | /' "$WORK/retention.log"
	assert "oldest mysql artefacts pruned to keep=2" test \
		"$(stored | grep -c mysql-shop)" -eq 2
	refute "20200101 artefact deleted" test -e "$STORAGE/mysql-shop.20200101-0000.gz.enc"
	assert "postgres artefacts untouched by mysql retention" test \
		"$(stored | grep -c pg-shop)" -eq 1
	ok "artefact count went from $before to $(stored_count)"

	info "a failing source is reported as a failure"
	# Exit status is deliberately not asserted: dumptruck currently exits 0 even
	# when every source fails, so cron sees a silent success. Until that is
	# fixed, the pushed metric is the only failure signal, which is exactly why
	# it is worth asserting here.
	/app/dumptruck.py "$WORK/broken.json" > "$WORK/fail.log" 2>&1 || true
	sed 's/^/  | /' "$WORK/fail.log"
	refute "no artefact stored for the failed source" bash -c \
		"find $STORAGE -name 'unreachable.*' | grep -q ."
	assert "failure metric pushed" grep -q \
		'instance/unreachable backup_status{.*} -1' "$PUSHED"
	for secret in "$ENC" "$MYSQL_PW"; do
		refute "failure log is free of ${secret:0:12}..." grep -qa "$secret" "$WORK/fail.log"
	done
	assert "no dump left behind after failure" test "$(find "$WORK" -name '*.enc' | wc -l | tr -d ' ')" -eq 0

	info "summary"
	if [[ $failures -eq 0 ]]; then
		printf '  \033[32mall checks passed\033[0m\n'
		return 0
	fi
	printf '  \033[31m%d check(s) failed\033[0m\n' "$failures"
	return 1
}

main "$@"
