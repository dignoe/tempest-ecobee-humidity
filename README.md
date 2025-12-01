# tempest-ecobee-humidity
Update the humidity setting on an Ecobee thermostat with the upcoming forecast from a WeatherFlow Tempest personal weather station.

## Configuration
1. Copy the sample config and add your credentials:
	```bash
	cp config.example.yml config.yml
	$EDITOR config.yml
	```
2. The installer copies this file to `/etc/tempest-ecobee-humidity/config.yml`. You can also edit that file directly after installation.

## Install as a systemd service
The Ruby script now runs once and relies on `systemd` to execute hourly via a timer.

Requirements:
- Linux host with systemd
- Ruby (system version is fine)
- Network access to api.ecobee.com and the Tempest API

Install steps:
```bash
sudo ./install_service.sh
```
The installer will:
- Copy `set_humidity.rb` to `/opt/tempest-ecobee-humidity`
- Place your config at `/etc/tempest-ecobee-humidity/config.yml` (copying the repo `config.yml` if present)
- Store Ecobee authentication tokens in `/var/lib/tempest-ecobee-humidity`
- Register and enable `tempest-ecobee-humidity.service` and its hourly timer
- Trigger an initial run so you can capture the Ecobee PIN if needed

## Managing the service
- Start an on-demand run: `sudo systemctl start tempest-ecobee-humidity.service`
- Check status/logs: `sudo systemctl status tempest-ecobee-humidity.service`
- Stop future hourly runs: `sudo systemctl stop tempest-ecobee-humidity.timer`
- Re-enable hourly runs (after stopping): `sudo systemctl start tempest-ecobee-humidity.timer`
- Disable autostart at boot: `sudo systemctl disable tempest-ecobee-humidity.timer`

When the timer is enabled (default after install) it runs the sync every hour and survives reboots because the timer is marked as persistent.

## Updating the install
Pull the latest changes and rerun `sudo ./install_service.sh`. The script reapplies the service files and restarts the timer.

## Docker (optional legacy workflow)
The previous Docker-based workflow is still available if you prefer to run the project in a container:

```bash
cp docker-compose.example.yml docker-compose.yml
docker compose up --build
```

Run detached after the initial Ecobee authorization:

```bash
docker compose up --build -d
```