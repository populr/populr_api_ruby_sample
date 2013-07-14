$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..'))

require 'twilio-ruby'
require 'mongoid'
require 'pony'
require 'ostruct'
require 'sinatra/r18n'
require 'populr'
require 'resque'
require 'resque/errors'
require 'open-uri'
require 'uri'

require 'lib/pop_delivery_configuration'
require 'lib/pop_embed'
require 'lib/pop_creation_job'
require 'lib/pop_creation_worker'
require 'helpers'

include R18n::Helpers

# bind the translation module into the global scope ourselves
# since the library just links it into the sinatra application
# and we need it in the background task as well
R18n.default_places = 'i18n'
R18n.set('en')
t = R18n.t


ENV["MONGO_HOST"] ||= "localhost:27017"
ENV["MONGO_DB"] ||= "my_db"

ENV["SMTP_AUTH_USER"] ||= ""
ENV["SMTP_AUTH_PASSWORD"] ||= ""
ENV["SMTP_MAILHUB"] ||= "smtp.sendgrid.net:587"

ENV["TWILLIO_API_KEY"] ||= ''
ENV["TWILLIO_API_SECRET"] ||= ''
ENV["TWILLIO_NUMBER"] ||= '+15404405900'

ENV["REDISTOGO_URL"] ||= 'redis://localhost:6379/'
ENV["DOMAIN"] ||= 'http://localhost:5000'

Mongoid.configure do |config|
  config.sessions = {
    :default => {:hosts => [ENV["MONGO_HOST"]], :database => ENV["MONGO_DB"]}
  }
  if ENV["MONGO_USER"]
    config.sessions[:default][:username] = ENV["MONGO_USER"]
    config.sessions[:default][:password] = ENV["MONGO_PASSWORD"]
  end
end

Pony.options = {
  :from => "noreply@populate.me",
  :via => :smtp,
  :via_options => {
    :address => ENV['SMTP_MAILHUB'].split(':').first,
    :port => ENV['SMTP_MAILHUB'].split(':').last,
    :authentication => :plain,
    :user_name => ENV['SMTP_AUTH_USER'],
    :password => ENV['SMTP_AUTH_PASSWORD'],
    :domain => ENV['SMTP_MAILHUB'],
    :enable_starttls_auto => true
  },
}

redis_uri = URI.parse(ENV["REDISTOGO_URL"])
Resque.redis = Redis.new(:host => redis_uri.host, :port => redis_uri.port, :password => redis_uri.password)

