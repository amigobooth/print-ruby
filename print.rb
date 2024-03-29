require "json"
require "faraday"
require "timeout"
require "highline/import"
require "fileutils"

class Client

  attr_reader :token

  def authenticate
    username = ask("Username: ", String)
    password = ask("Password: ", String) { |q| q.echo = "*" }

    response = basic_connection(username, password).post do |req|
      req.url "/api/v1/me/keys"
      req.headers["Accept"]       = "application/json"
      req.headers["Content-Type"] = "application/json"
      req.body = JSON.generate({ description: "AmigoBooth Print Service" })
    end

    body = JSON.parse(response.body)
    if body["token"]
      @token = body["token"]

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
    else
      puts "\nUsername and/or password incorrect. Please try again."
      authenticate
    end
  end

  def load_and_show_events
    response = token_connection.get do |req|
      req.url "/api/v1/me/events"
      req.headers["Accept"]       = "application/json"
      req.headers["Content-Type"] = "application/json"
      req.headers["X-AmigoBooth-Token"] = token
    end

    events = JSON.parse(response.body)

    puts "\n### My Events ###"
    puts "ID\t Date      \t Name"
    events.each do |event|
      puts "#{event["id"]}\t #{event["date"]}\t #{event["name"]}"
    end

    event_id_to_print = ask("Which event would you like to watch the printer queue? ", Integer) { |q| q.in = events.map{|e| e["id"]} }

    puts "\n ### Watching '#{events.detect{|e| e["id"] == event_id_to_print}["name"]}' for prints ###"

    print_ids = []

    loop do
      response = token_connection.get do |req|
        req.url "/api/v1/me/events/#{event_id_to_print}/prints"
        req.headers["Accept"]       = "application/json"
        req.headers["Content-Type"] = "application/json"
        req.headers["X-AmigoBooth-Token"] = token
      end

      prints = JSON.parse response.body
      if prints.any?
        puts "\nProcessing #{prints.count} prints in the queue."

        prints.reject{|p| print_ids.include? p["id"] }.each do |print|
          puts "\n Downloading shot ##{print["shot"]["id"]} from #{print["shot"]["photo"]["edited_url"]}"
          response = Faraday.get print["shot"]["photo"]["edited_url"]
          FileUtils.mkdir_p "prints"
          File.open(%(prints/#{print["id"]}.jpg), 'w') { |f| f.write(response.body) }

          puts "Adding ##{print["id"]} to the print queue"
          `lp #{File.expand_path(%(prints/#{print["id"]}.jpg))}`

          puts "Removing ##{print["shot"]["id"]} from remote queue"
          response = token_connection.delete do |req|
            req.url "/api/v1/me/events/#{event_id_to_print}/prints/#{print["id"]}"
            req.headers["Accept"]       = "application/json"
            req.headers["Content-Type"] = "application/json"
            req.headers["X-AmigoBooth-Token"] = token
          end
        end
      end
      sleep 5
    end
  end

  private

  def basic_connection(username, password)
    @basic_connection ||= Faraday.new(url: "https://amigobooth.com") do |faraday|
      faraday.request :basic_auth, username, password
      faraday.adapter Faraday.default_adapter
    end
  end

  def token_connection
    @token_connection ||= Faraday.new(url: "https://amigobooth.com") do |faraday|
      faraday.adapter Faraday.default_adapter
    end
  end

end

client = Client.new
client.authenticate
client.load_and_show_events
