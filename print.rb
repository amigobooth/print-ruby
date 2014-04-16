require "bundler/setup"
require "json"
require "faraday"
require "timeout"

Bundler.require

username = ask("Username: ", String)
password = ask("Password: ", String) { |q| q.echo = "*" }

basic_connection = Faraday.new(url: "https://amigobooth.com") do |faraday|
  faraday.request :basic_auth, username, password
  faraday.adapter Faraday.default_adapter
end

response = basic_connection.post do |req|
  req.url "/api/v1/me/keys"
  req.headers["Accept"]       = "application/json"
  req.headers["Content-Type"] = "application/json"
  req.body = JSON.generate({ description: "AmigoBooth Print Service" })
end

token = JSON.parse(response.body)["token"]

token_connection = Faraday.new(url: "https://amigobooth.com") do |faraday|
  faraday.adapter Faraday.default_adapter
end

response = token_connection.get do |req|
  req.url "/api/v1/me/events"
  req.headers["Accept"]       = "application/json"
  req.headers["Content-Type"] = "application/json"
  req.headers["X-AmigoBooth-Token"] = token
end

events = JSON.parse(response.body)

# Quit with Ctrl+C
# Cleanup queue and logout
trap "INT" do
  Thread.new {
    puts "Stopping and revoking API key..."

    token_connection.delete do |req|
      req.url "/api/v1/me/keys/#{token}"
      req.headers["Accept"]       = "application/json"
      req.headers["Content-Type"] = "application/json"
      req.headers["X-AmigoBooth-Token"] = token
    end
  }.join

  raise Interrupt
end

puts "\n### My Events ###"
puts "ID\t Date      \t Name"
events.each do |event|
  puts "#{event["id"]}\t #{event["date"]}\t #{event["name"]}"
end

event_id_to_print = ask("Which event would you like to watch the printer queue? ", Integer) { |q| q.in = events.map{|e| e["id"]} }

puts "\n ### Watching '#{events.detect{|e| e["id"] == event_id_to_print}["name"]}' for prints ###"
loop do
  response = token_connection.get do |req|
    req.url "/api/v1/me/events/#{event_id_to_print}/prints"
    req.headers["Accept"]       = "application/json"
    req.headers["Content-Type"] = "application/json"
    req.headers["X-AmigoBooth-Token"] = token
  end

  shots_to_print = JSON.parse response.body
  if shots_to_print.any?
    puts "Pulled #{shots_to_print.count} to print."
  end
  sleep 5
end
