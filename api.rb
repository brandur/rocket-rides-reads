require "json"
require "sinatra"

require_relative "./config"

class API < Sinatra::Base
  set :server, %w[puma]
  set :show_exceptions, false

  post "/rides" do
    user = authenticate_user(request)
    params = validate_params(request)

    DB.transaction(isolation: :serializable) do
      ride = Ride.create(
        distance: params["distance"],
        user_id: user.id,
      )
      update_user_min_lsn(user)

      [201, JSON.generate(serialize_ride(ride))]
    end
  end

  get "/rides/:id" do |id|
    user = authenticate_user(request)

    name = select_replica(user)
    $stdout.puts "Reading ride #{id} from server '#{name}'"

    ride = Ride.server(name).first(id: id)
    if ride.nil?
      halt 404, JSON.generate(wrap_error(
        Messages.error_not_found(object: "ride", id: id)
      ))
    end

    [200, JSON.generate(serialize_ride(ride))]
  end
end

#
# models
#

class Ride < Sequel::Model
end

class User < Sequel::Model
end

#
# other modules/classes
#

module Messages
  def self.ok
    "Payment accepted. Your pilot is on their way!"
  end

  def self.error_auth_invalid
    "Credentials in Authorization were invalid."
  end

  def self.error_auth_required
    "Please specify credentials in the Authorization header."
  end

  def self.error_not_found(object:, id:)
    "Object of type '#{object}' with ID '#{id}' was not found."
  end

  def self.error_require_float(key:)
    "Parameter '#{key}' must be a floating-point number."
  end

  def self.error_require_param(key:)
    "Please specify parameter '#{key}'."
  end
end

#
# helpers
#

def authenticate_user(request)
  auth = request.env["HTTP_AUTHORIZATION"]
  if auth.nil? || auth.empty?
    halt 401, JSON.generate(wrap_error(Messages.error_auth_required))
  end

  # This is obviously something you shouldn't do in a real application, but for
  # now we're just going to trust that the user is whoever they said they were
  # from an email in the `Authorization` header.
  user = User.first(email: auth)
  if user.nil?
    halt 401, JSON.generate(wrap_error(Messages.error_auth_invalid))
  end

  user
end

# Selects the name of a random replica that can be passed to a Sequel `#server`
# invocation to run a read a read query against a replica instead of the
# primary.
#
# Uses the given user's `min_lsn` to determine which replicas are caught up
# enough to be usable such that we will never have a stale read.
#
# In cases where no appropriate replica candidates exist, then we return
# `:default` which maps to the primary.
def select_replica(user)
  # If the user's `min_lsn` is `NULL` then they haven't performed an operation
  # yet, and we don't yet know if we can use a replica yet. Default to the
  # primary.
  return :default if user.min_lsn.nil?

  # exclude :default at the zero index
  replica_names = DB.servers[1..-1].map { |name| name.to_s }

  res = DB[Sequel.lit(<<~eos), replica_names, user.min_lsn]
    SELECT name
    FROM replica_statuses
    WHERE name IN ?
      AND pg_wal_lsn_diff(last_lsn, ?) >= 0;
  eos

  # If no candidates are caught up enough, then go to the primary.
  return :default if res.nil? || res.empty?

  # Return a random replica name from amongst the candidates.
  candidate_names = res.map { |res| res[:name].to_sym }
  candidate_names.sample
end

def serialize_ride(ride)
  {
    "distance": ride.distance.round(1),
    "id":       ride.id,
    "user_id":  ride.user_id,
  }
end

# Updates a user's `min_lsn` (log sequence number) so that we can start making
# determinations as to whether it's safe for them to read from replicas. Note
# that this is an update operation and always executes against the primary.
def update_user_min_lsn(user)
  User.
    where(id: user.id).
    update(Sequel.lit("min_lsn = pg_current_wal_lsn()"))
end

def validate_params(request)
  {
    "distance" => validate_params_float(request, "distance"),
  }
end

def validate_params_float(request, key)
  val = validate_params_present(request, key)

  # Float as opposed to to_f because it's more strict about what it'll take.
  begin
    Float(val)
  rescue ArgumentError
    halt 422, JSON.generate(wrap_error(Messages.error_require_float(key: key)))
  end
end

def validate_params_present(request, key)
  val = request.POST[key]
  return val if !val.nil? && !val.empty?
  halt 422, JSON.generate(wrap_error(Messages.error_require_param(key: key)))
end

# Wraps a message in the standard structure that we send back for error
# responses from the API. Still needs to be JSON-encoded before transmission.
def wrap_error(message)
  { error: message }
end

#
# run
#

if __FILE__ == $0
  port = ENV["API_PORT"] || abort("need API_PORT")
  API.run!(port: port)
end
