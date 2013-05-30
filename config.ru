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

run Rack::URLMap.new \
  "/"       => Sinatra::Application,
  "/resque" => Resque::Server.new
