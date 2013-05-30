# Gemfile
require "rubygems"
require "bundler/setup"
require "sinatra"
require 'sinatra/base'
require 'resque/server'

require File.join(File.dirname(__FILE__), 'config', 'boot')

require "./app"

set :run, false
set :raise_errors, true

Resque::Server.use Rack::Auth::Basic do |username, password|
  username == 'admin' && password == 'is0BET4mkFM9KqkTgEEt2lz9fOZFsrKKcSIBqP6B6rN7U62v8alXhvjEsxVu3xl'
end

run Rack::URLMap.new \
  "/"       => Sinatra::Application,
  "/resque" => Resque::Server.new
