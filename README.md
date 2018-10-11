# Dumptruck

Simple solution for backing up MySQL, PostgreSQL and Mongo databases with Swift and Rclone.

## Configuration

Configuration is done via JSON files, i.e. `daily.json` and a crontab.
Each config file should contain a JSON object with the following keys:

- `encryption`: Password (string) used to encrypt the dumped files.
- `sources`: List of databases to dump.
- `storage`: List of storage locations for storing the encrypted dumps.
- `monitor`: Optional prometheus push gateway (with basic auth) for reporting successful backups.

Please see `daily.json.sample` for an example.

Every database specified under the `sources` key is dumped, encrypted and uploaded to all storage locations listed under `storage`.
Timestamps of successful backups are exported to a [Prometheus push gateway](https://prometheus.io/docs/instrumenting/pushing/) with basic auth configured under `monitor`.


### Sources

```json
{
  "name": "db-prod",  // internal name for this data source - used to generate filenames
  "dbtype": "mysql",  // supported databases are 'mysql', 'postgres' and 'mongo'
  "host": "db-galera-prod-0",
  "database": "data",  // actual database name
  "username": "backup",  // database credentials
  "password": "********",
  "keep": 14,  // older backups will be deleted if there are more than this many
  "tunnel": "backup@jumphost"  // optional user@host when the connection requires SSH tunneling
}
```

To backup databases which are not connected to the same network you can specify a value for `tunnel` like `user@jumphost`. During backup an SSH tunnel will be used to forward traffic to the database, this requires an appropriate SSH key.

### Storage

To store our backups in Swift buckets we need to supply credentials for a user:

```json
{
  "type": "swift",
  "auth_url": "https://ouropenstack:5000/v3",
  "username": "backup",
  "user_domain_id": "********",
  "password": "********",
  "project_id": "********",
  "container_url": "https://ourswift/swift/v1/ourbackups"
}
```

We can also use Rclone to store our dumps somewhere. This will require an additional Rclone config file `rclone`.
```json
{
  "type: "rclone",
  "remote: "sftphost",  // name of a remote to use from the rclone config file
  "target: "backups"  // store backups in sftphost:backups/<dump>
}
```

### Crontab

The `crontab` determines when and how often backups should be performed. Backups can be performed with different intervals by adding entries for different config files, i.e.:

```crontab
0  3  *  *  *  /app/dumptruck.py  /app/daily.json
0  4  0  *  *  /app/dumptruck.py  /app/weekly.json
```

## Deployment

Though the crontab should be usable with any cron demon we use [supercronic](https://github.com/aptible/supercronic) to run everything in the foreground with `supercronic <path to crontab>`.

### Kubernetes, Cloud Foundry (Docker)

A public docker build of this repo is available at DockerHub [meshcloud/dumptruck](https://hub.docker.com/r/meshcloud/dumptruck/).

The default entrypoint supports environment variables for easily bootstrapping a single backup configuration without having to build your own docker image on top of the official build.

`CRONTAB`: a simple cronstring like `0 1 * * * /app/dumptruck.py /app/config.json`. Must point to `/app/config.json`. 

`CONFIG_JSON`: the full configuration that will be made available at `/app/config.json` at runtime.

`CONFIG_RCLONE`: a Rclone configuration that will be made available at `/app/rclone` at runtime.

See [manifest-docker.yml](manifest-docker.yml) for an example of how we can use this approach to deploy to Cloud Foundry.
You can of course also launch the container with a different entrypoint and skip this default bootstrapping.

## Restore

The dumptruck can also be used to restore databases.
When you execute `dumptruck.py <path to config> <source name> <dump file>` dumptruck will use the configuration options from the specified config file to

- download the specified dump file (use the full filename) from a storage provider,
- decrypt that dump with the configured password,
- connect to the database with the given source name and send the dump to a restore command.

Depending on the database state it might be necessary to drop tables or create the database first.
