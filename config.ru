# Gemfile
require "rubygems"
require "bundler/setup"
require "sinatra"
require 'sinatra/base'
require "sinatra/reloader"
require "./app"

set :run, false
set :raise_errors, true

run Sinatra::Application