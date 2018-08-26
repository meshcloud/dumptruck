# Dumptruck

Simple solution for backing up MySQL and Mongo databases as Swift objects.

## Configuration

Configuration is done via JSON files, i. e. `daily.json` and a crontab.
Each config file should contain a JSON object with the following keys:

- `sources`: List of databases to dump.
- `encryption`: Password (string) used to encrypt the dumped files.
- `storage`: List of OpenStack Swift containers for storing the encrypted dumps.
- `monitor`: Prometheus push gateway (with basic auth) for reporting successful backups.

Please see `daily.json.sample` for a more detailed example.

Every database specified under the `sources` key is dumped, encrypted and uploaded to all containers listed under `storage`. The `keep` key specifies how many backups should be kept and is set per source.
Timestamps of successful backups are exported to a [Prometheus push gateway](https://prometheus.io/docs/instrumenting/pushing/) with basic auth configured under `monitor`.

The `crontab` determines when and how often backups should be performed. Backups can be performed with different intervals by adding entries for different config files, i.e.:

```crontab
0  3  *  *  *  /app/dumptruck.py  /app/daily.json
0  4  0  *  *  /app/dumptruck.py  /app/weekly.json
```

To backup databases which are not connected to the same network you can specify a value for `tunnel` like `user@jumphost`. During backup an SSH tunnel will be used to forward traffic to the database, this requires an appropriate SSH key.

## Deployment

Though the crontab should be usable with any cron demon we use [supercronic](https://github.com/aptible/supercronic) to run everything in the foreground with `supercronic <path to crontab>`.

### Cloud Foundry (Buildpack)

Make sure all required config files exist in the current directory:

- JSON files (i.e. `daily.json`)
- `crontab` file referencing your JSON files
- optional `key` file containing the private key for ssh tunneling

These files will be stored under `/app` and should be referenced accordingly.

Edit the `manifest.yml` to include any db services you need to connect to and increase memory/disk quotas according to your database sizes. When everythin is set run `cf push` to deploy the dumptruck.

> Note: Do install the required database-specific client tooling, we use CF [multi-buildpack](https://github.com/cloudfoundry/multi-buildpack) in combination with [apt-buildpack](https://github.com/cloudfoundry/apt-buildpack). Unfortunately we cannot install postgresql-client tooling this way as it does not cope well with installation in a non-standard path as it is implemented by apt-buildpack. If you need to backup postgresql databases, use the docker-based deployment method below.

### Kubernetes, Cloud Foundry (Docker)

A public docker build of this repo is available at DockerHub [meshcloud/dumptruck](https://hub.docker.com/r/meshcloud/dumptruck/).

The default entrypoint supports two environment variables for easily bootstrapping a single backup configuration without having to build your own docker image on top of the official build.

`CRONTAB`: a simple cronstring like `0 1 * * * /app/dumptruck.py /app/config.json`. Must point to `/app/config.json`. 

`CONFIG_JSON`: the full configuration that will be made available at `/app/config.json` at runtime.

See [manifest-docker.yml](manifest-docker.yml) for an examlple of this approach. You can of course also launch the container with a different entrypoint and skip this default bootstrapping.