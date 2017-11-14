require "net/http"
require "securerandom"

require_relative "./api"

class Simulator
  def initialize(port:)
    self.port = port
  end

  def run
    loop do
      run_once(sleep_before_get: rand * 2)
      duration = rand * 2
      $stdout.puts "Sleeping for #{duration}"
      sleep(duration)
    end
  end

  def run_once(sleep_before_get: 0.0)
    user = User.find_or_create(email: "user@example.com")

    http = Net::HTTP.new("localhost", port)
    request = Net::HTTP::Post.new("/rides")
    request["Authorization"] = user.email
    request.set_form_data({
      "distance" => rand * (MAX_DISTANCE - MIN_DISTANCE) + MIN_DISTANCE
    })
    response = http.request(request)
    $stdout.puts "Response: status=#{response.code} body=#{response.body}"

    data = JSON.parse(response.body, symbolize_names: true)

    sleep(sleep_before_get)

    request = Net::HTTP::Get.new("/rides/#{data[:id]}")
    request["Authorization"] = user.email
    response = http.request(request)
    $stdout.puts "Response: status=#{response.code} body=#{response.body}"
  end

  #
  # private
  #

  MAX_DISTANCE = 1000.0
  private_constant :MAX_DISTANCE
  MIN_DISTANCE = 5.0
  private_constant :MIN_DISTANCE

  attr_accessor :port
end

#
# run
#

if __FILE__ == $0
  # so output appears in Forego
  $stderr.sync = true
  $stdout.sync = true

  port = ENV["API_PORT"] || abort("need API_PORT")

  # wait a moment for the API to come up
  sleep(3)

  Simulator.new(port: port).run
end
