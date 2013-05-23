# Gemfile
require "rubygems"
require "bundler/setup"
require "sinatra"
require 'sinatra/base'
require 'rack/ssl'


require "./app"

set :run, false
set :raise_errors, true

run Sinatra::Application