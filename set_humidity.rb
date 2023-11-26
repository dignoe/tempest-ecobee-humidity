#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'yaml'
require 'optparse'
# Rollbar for errors

# TODO: turn into docker image, cron job to run every hour

HOURS = 18 || ENV['HOURS']
MAX_HUMIDITY = 45 || ENV['MAX_HUMIDITY']
MIN_HUMIDITY = 15
TEMPEST_BASE_URI = 'https://swd.weatherflow.com/swd/rest/better_forecast'.freeze

# Use ENV variables set by docker instead of YAML file
TEMPEST_TOKEN = ENV['TEMPEST_TOKEN']
STATION_ID = ENV['TEMPEST_STATION_ID']
ECOBEE_API_KEY = ENV['ECOBEE_API_KEY']

def tempest_data
  url = "#{TEMPEST_BASE_URI}?units_temp=f&station_id=#{STATION_ID}" \
        "&token=#{TEMPEST_TOKEN}"

  JSON.parse(Net::HTTP.get(URI(url)))
end

# Gets the lowest temp currently, or forecasted in the next HOURS
def forecasted_low_temp
  response = tempest_data

  temps = [response['current_conditions']['air_temperature']]
  temps +=
    response['forecast']['hourly'].sort_by { |f| f['time'] }
                                  .slice(0, HOURS)
                                  .map { |f| f['air_temperature'] }
  min_temp = temps.min

  p "Lowest temp is #{min_temp}º"

  min_temp
end

# The humidity level to set
def target_humidity_level
  h = (0.5 * forecasted_low_temp + 25).ceil
  [[MIN_HUMIDITY, h].max, MAX_HUMIDITY].min
end

def get_ecobee_pin
  url = "https://api.ecobee.com/authorize?response_type=ecobeePin" \
        "&client_id=#{ECOBEE_API_KEY}&scope=smartWrite"

  JSON.parse(Net::HTTP.get(URI(url)))
end

def get_ecobee_token_from_challenge(token)
  url = "https://api.ecobee.com/token?grant_type=ecobeePin" \
        "&code=#{token}&client_id=#{ECOBEE_API_KEY}"

  JSON.parse(Net::HTTP.post(URI(url)))
end

def refresh_ecobee_token
  url = "https://api.ecobee.com/token?grant_type=refresh_token" \
        "&refresh_token=#{ecobee_refresh_token}&client_id=#{ECOBEE_API_KEY}"

  response = JSON.parse(Net::HTTP.post(URI(url)))
  save_ecobee_token!(response)
end

def save_ecobee_token!(response)
  @ecobee_access_token = response['access_token']
  #@ecobee_refresh_token = response['refresh_token']
  # save refresh token
end

# Requests an auth token from Ecobee
def authorize_ecobee
  response = get_ecobee_pin

  p "Sign in to Ecobee and enter the pin in My Apps #{response['ecobeePin']}"
  challenge = STDIN.gets.chomp

  p "Press enter when you've added your pin"
  STDIN.gets

  response = get_ecobee_token_from_challenge(response['code'])
  save_ecobee_token!(response)

  p 'Authorization successful'
end

def set_ecobee_humidity_level

end

def humidifier_on?
  true
end

def update_humidity?(t)
  true
end

# Sets the humidity level on the Ecobee thermostat
def set_humidity
  return unless humidifier_on?

  t = target_humidity_level
  p "Set humidity to #{t}%"

  return unless update_humidity?(t)

  set_ecobee_humidity_level
end

# Use optparse to either request a new Ecobee token or run normally

# Authorize script
# authorize_ecobee
# Get list of thermostats
# save thermostat identifier
# default

# Default run script
# Refresh Ecobee token
# Get Ecobee status
# If humidifier is on, get forecast and determine humidity level
# If humidity level changed, update humidity level

set_humidity
