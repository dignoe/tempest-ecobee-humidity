#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/https'
require 'json'
require 'yaml'

# Set variables

CONFIG = YAML.load_file('/data/config.yml')
HOURS = CONFIG['hours']
MAX_HUMIDITY = CONFIG['max_humidity']
MIN_HUMIDITY = CONFIG['min_humidity']

TEMPEST_TOKEN = CONFIG['tempest']['token']
STATION_ID = CONFIG['tempest']['station_id']
TEMPEST_URI = 'https://swd.weatherflow.com/swd/rest/better_forecast?units_temp=f' \
              "&station_id=#{STATION_ID}&token=#{TEMPEST_TOKEN}"

ECOBEE_HTTP = Net::HTTP.new('api.ecobee.com', 443)
ECOBEE_HTTP.use_ssl = true
ECOBEE_API_KEY = CONFIG['ecobee']['api_key']

# Tempest

def tempest_data
  JSON.parse(Net::HTTP.get(URI(TEMPEST_URI)))
end

# Ecobee authentication

# Prompts user to authenticate if there is no token
# Refreshes the token if it's expired
def authorize_ecobee
  return if ecobee_token?

  response = request_ecobee_pin

  p "Sign in to Ecobee and enter the pin in My Apps #{response['ecobeePin']}."

  request_ecobee_token_from_pin(response)
end

# do we have a token from Ecobee?
def ecobee_token?
  load_ecobee_token
  return false if @ecobee_auth.nil?

  refresh_ecobee_token if @ecobee_auth[:expires_at] < (Time.now + 60)

  true
end

def load_ecobee_token
  return unless File.exist?('/data/ecobee_auth.yml')

  @ecobee_auth = YAML.load_file('/data/ecobee_auth.yml', symbolize_names: true)
end

def save_ecobee_token!(response)
  @ecobee_auth = {
    token: response['access_token'],
    type: response['token_type'],
    expires_at: Time.now + response['expires_in'].to_i,
    refresh_token: response['refresh_token']
  }

  File.write('/data/ecobee_auth.yml', YAML.dump(@ecobee_auth))
end

def request_ecobee_pin
  url = "/authorize?response_type=ecobeePin&client_id=#{ECOBEE_API_KEY}&scope=smartWrite"
  request = Net::HTTP::Get.new(url)
  response = ECOBEE_HTTP.request(request)

  unless response.code == '200'
    p JSON.parse(response.body)['status']['message']
    raise 'Getting Ecobee PIN failed'
  end

  JSON.parse(response.body)
end

def request_ecobee_token_from_pin(pin_response)
  expires_at = Time.now + (60 * pin_response['expires_in'].to_i)
  data = {
    grant_type: 'ecobeePin',
    code: pin_response['code'],
    client_id: ECOBEE_API_KEY
  }

  poll_for_auth_token(expires_at, pin_response['interval'].to_i, data)
end

def ecobee_auth_token_request(data)
  request = Net::HTTP::Post.new('/token')
  request.set_form_data(data)
  ECOBEE_HTTP.request(request)
end

def poll_for_auth_token(expires_at, interval, data)
  while Time.now < expires_at
    sleep interval

    response = ecobee_auth_token_request(data)

    next if response.code == '401'
    raise response.body['error_description'] unless response.code == '200'

    save_ecobee_token!(JSON.parse(response.body))
    p 'Authorization successful'
    return
  end

  raise 'Ecobee PIN authorization expired'
end

def refresh_ecobee_token
  data = {
    grant_type: 'refresh_token',
    refresh_token: @ecobee_auth[:refresh_token],
    client_id: ECOBEE_API_KEY
  }

  request = Net::HTTP::Post.new('/token')
  request.set_form_data(data)
  response = ECOBEE_HTTP.request(request)

  raise 'Refreshing Ecobee token failed' unless response.code == '200'

  save_ecobee_token!(JSON.parse(response.body))
end

def ecobee_auth_header
  "#{@ecobee_auth[:type]} #{@ecobee_auth[:token]}"
end

# Calculate & set humidity

def active_thermostats(json)
  therms = json['thermostatList'].select do |t|
    t['settings']['hasHumidifier'] && t['settings']['humidifierMode'] == 'manual'
  end

  therms.map do |t|
    { identifier: t['identifier'], name: t['name'], humidity: t['settings']['humidity'].to_i }
  end
end

# find thermostats that have humidifier and humidifier is on
def humidifier_on?
  data = { selection: {
    selectionType: 'registered', includeSettings: true, includeEquipmentStatus: true
  } }.to_json
  request = Net::HTTP::Get.new("/1/thermostat?body=#{data}")
  request['Authorization'] = ecobee_auth_header
  request['Content-Type'] = 'application/json;charset=UTF-8'
  response = ECOBEE_HTTP.request(request)

  @thermostats = active_thermostats(JSON.parse(response.body))

  @thermostats.any?
end

# The humidity level to set
def target_humidity_level
  humidity_level = (0.5 * forecasted_low_temp + 25).ceil
  target = [[MIN_HUMIDITY, humidity_level].max, MAX_HUMIDITY].min

  p "Humidity level should be set to #{target}%"
  target
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

  p "Lowest forecasted temperature in the next #{HOURS} hours is #{min_temp}º"

  min_temp
end

def update_humidity?(target_humidity)
  @thermostats.reject! { |t| t[:humidity] == target_humidity }
  @thermostats.any?
end

def ecobee_update_data(target_humidity)
  {
    selection: {
      selectionType: 'thermostats',
      selectionMatch: @thermostats.map { |t| t[:identifier] }.join(',')
    },
    thermostat: { settings: { humidity: target_humidity } }
  }.to_json
end

def push_ecobee_humidity_level(target_humidity)
  p "Updating target humidity level on #{@thermostats.map { |t| t[:name] }.join(', ')}"

  request = Net::HTTP::Post.new('/1/thermostat')
  request['Authorization'] = ecobee_auth_header
  request['Content-Type'] = 'application/json;charset=UTF-8'
  request.body = ecobee_update_data(target_humidity)
  response = ECOBEE_HTTP.request(request)

  p 'Updating humdity failed' unless response.code == '200'
end

# Sets the humidity level on the Ecobee thermostat
def set_humidity
  p 'Checking humidifier status...'
  return unless humidifier_on?

  t = target_humidity_level

  if update_humidity?(t)
    push_ecobee_humidity_level(t)
  else
    p 'No update needed'
  end
end

def run
  loop do
    set_humidity
    sleep 3600
  end
end

authorize_ecobee
run
