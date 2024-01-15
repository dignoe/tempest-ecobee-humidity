# tempest-ecobee-humidity
Update the humidity setting on an Ecobee thermostat with the upcoming forecast from a WeatherFlow Tempest personal weather station.

## Setup

`cp config.example.yml config.yml`

Enter your Tempest token, station id, and Ecobee API key.

`cp docker-compose.example.yml docker-compose.yml`

Run it for the first time to get Ecobee authentication
`docker compose up --build`

After you get an Ecobee token, you can exit and restart with
`docker compose up --build -d`