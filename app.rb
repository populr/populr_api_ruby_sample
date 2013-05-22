require 'rubygems'
require 'populr'
require 'json'
require 'open-uri'
require 'twilio-ruby'
require 'mongoid'
require 'pony'
require 'erb'
require 'ostruct'
require 'sinatra/r18n'
require 'csv'

include R18n::Helpers

class PopDeliveryConfiguration
  include Mongoid::Document
  field :api_key
  field :api_env
  field :template_id
  field :delivery_config
end

class PopEmbed < PopDeliveryConfiguration; end

class PopCreationJob < PopDeliveryConfiguration
  field :queued_rows, :type => Array, :default => []
  field :finished_rows_status, :type => Array, :default => []
  field :failed_row_count, :type => Integer, :default => 0
  field :finished, :default => false
  field :email
end

Thread.new do
  while true do
    job = PopCreationJob.where(:finished => false).first
    unless job
      sleep 1
      next
    end

    begin
      @populr = Populr.new(job.api_key, url_for_environment_named(job.api_env))
      @template = @populr.templates.find(job.template_id)

      puts "Processing job with delivery config: #{job.delivery_config}"

      for row in job.queued_rows
        values = CSV.parse_line(row)
        data = {'file_regions' => {}, 'tags' => {}, 'embed_regions' => {}}
        data['slug'] = values.first
        vindex = 1

        for tag in @template.api_tags
          data['tags'][tag] = values[vindex]
          vindex += 1
        end
        for region, info in @template.api_regions
          if info['type'] == 'embed'
            data['embed_regions'][region] ||= []
            data['embed_regions'][region].push(values[vindex])
          else
            data['file_regions'][region] ||= []
            data['file_regions'][region].concat(values[vindex].split(','))
          end
          vindex += 1
        end
        user_email = values[vindex]
        user_email = nil if user_email && user_email.empty?
        user_phone = values[vindex+1]
        user_phone = nil if user_phone && user_phone.empty?

        puts "processing row: #{row.to_json}"
        begin
          create_and_send_pop(@template, data, job.delivery_config, user_email, user_phone) { |pop_reference, pop|
            job.finished_rows_status.push(['true', pop_reference, pop.password])
          }
        rescue Exception => e
          job.finished_rows_status.push(['false', "\"#{e.to_s}\"", ''])
          job.failed_row_count += 1
        end
        puts "processed row with delivery #{user_email}, #{user_phone}"
      end

    rescue Exception => e
      puts e.to_s
      send_notification(job.email, {
        :instructions => t.job.exception_thrown(e.to_s),
        :url => '',
        :password => nil
      })
    else
      send_notification(job.email, {
        :instructions => t.job.successful_with_errors(job.failed_row_count),
        :url => "https://#{$servername}/job_results/#{job._id}",
        :password => nil
      })
    ensure
      puts "Finished Job #{job._id}. Final email delivered to #{job.email}"
      job.finished = true
      job.save!
    end
  end
end


configure do
  Mongoid.configure do |config|
    config.sessions = {
      :default => {
        :hosts => [ENV["MONGO_HOST"]],
        :database => ENV["MONGO_DB"],
        :password => ENV["MONGO_PASSWORD"],
        :username => ENV["MONGO_USER"]
      }
    }
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
end

set :public_folder, File.dirname(__FILE__) + '/public'
$servername = ""

before do
  if request.request_method == "POST"
    begin
    body_parameters = request.body.read
    params.merge!(JSON.parse(body_parameters))
    rescue
    end
  end
end


def find_api_connection
  @populr = Populr.new(params[:api_key], url_for_environment_named(params[:api_env])) if params[:api_key]

  if params[:embed]
    @embed = PopEmbed.find(params[:embed])
    @populr = Populr.new(@embed.api_key, url_for_environment_named(@embed.api_env))
    @template = @populr.templates.find(@embed.template_id)
  end

  halt "API Key Required" if request.path.include?('_/') && !@populr
end


get "/" do
  redirect('/index.html')
end

get "/help" do
  redirect('/help.html')
end

post "/callback/tracer_viewed" do
  return unless ENV["TWILLIO_API_KEY"]
  clicks = params[:tracer]['analytics']['clicks'] if params[:tracer]['analytics']
  clicks ||= 0
  twillio = Twilio::REST::Client.new(ENV["TWILLIO_API_KEY"], ENV["TWILLIO_API_SECRET"])
  twillio.account.sms.messages.create(
    :from => ENV["TWILLIO_NUMBER"],
    :to => params[:tracer]['name'],
    :body => t.tracer_callback.sms(clicks)
  )
end

get '/forms/' do
  return ''
end

get "/forms/:embed" do
  return '' if params[:embed] == 'undefined'
  find_api_connection
  erb :form
end

# Data Endpoints

get "/_/templates" do
  $servername = request.host_with_port

  find_api_connection
  begin
    return collection_listing(@populr.templates)
  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  end
end

get "/_/templates/:template_id/csv" do
  find_api_connection
  template = @populr.templates.find(params[:template_id])
  csv = csv_template_headers(template) + "\n"

  response.headers['content_type'] = "text/csv"
  attachment("#{template.name} Template.csv")
  response.write(csv)
end

post "/_/templates/:template_id/csv" do
  find_api_connection
  template = @populr.templates.find(params[:template_id])

  job = PopCreationJob.new(:api_key => params[:api_key], :api_env => params[:api_env])
  job.template_id = params[:template_id]
  job.delivery_config = {
      'action' => params[:delivery_action],
      'password' => params[:delivery_passwords] != nil,
      'password_sms' => params[:delivery_two_factor_passwords] != nil,
      'confirmation_email' => true
  }

  csv = params['file'][:tempfile].read
  csv_lines = csv.split("\r")
  # ensure that the first row of the CSV file hasn't been tampered with

  expected_headers = csv_template_headers(template)
  actual_headers = csv_lines[0]

  if expected_headers.parse_csv == actual_headers.parse_csv
    job.queued_rows = csv_lines[1..-1]
    job.email = params[:email]
    job.save!
    redirect('/thanks.html')
  else
    halt("Make sure the first row of your CSV file matches the template! The first row should have the following columns: #{expected_headers}")
  end
end

get "/job_results/:job" do
  job = PopCreationJob.find(params[:job])
  populr = Populr.new(job.api_key, url_for_environment_named(job.api_env))
  template = populr.templates.find(job.template_id)

  csv = csv_template_headers(template)
  csv += ",Success,Result,Password\r"
  job.queued_rows.count.times do |i|
    csv += job.queued_rows[i] + ',' + job.finished_rows_status[i].join(',') + "\r"
  end
  response.headers['content_type'] = "text/csv"
  attachment("Results.csv")
  response.write(csv)
end

get "/_/pops" do
  find_api_connection
  begin
    return collection_listing(@populr.templates.find(params[:template_id]).pops) if params[:template_id]
    return collection_listing(@populr.pops)
  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  end
end

post "/_/embeds" do
  return JSON.generate({"error" => "Please select an action"}) unless params[:action]
  return JSON.generate({"error" => "Please provide required fields."}) unless params[:api_key] && params[:api_env] && params[:template_id]

  find_api_connection
  delivery_config = {
    'action' => params[:action],
    'password' => params[:password_enabled] != nil,
    'password_sms' => params[:password_sms_enabled] != nil,
    'confirmation_email' => params[:confirmation]
  }
  properties = {:api_key => params[:api_key], :api_env => params[:api_env], :template_id => params[:template_id], :delivery_config => delivery_config}
  embed = PopEmbed.where(properties).first
  if !embed
    embed = PopEmbed.new(properties)
    embed.save!
  end
  return embed.to_json if embed
end


post "/_/embeds/:embed/build_pop" do
  find_api_connection
  begin
    return "Template Not Found" unless @template

    user_email = params[:pop_data]['populate_recipient_email']
    user_phone = sanitize_phone_number(params[:pop_data]['populate_recipient_phone'])
    data = params[:pop_data]

    create_and_send_pop(@template, data, @embed.delivery_config, user_email, user_phone) { |destination_url|
      return JSON.generate({"redirect_url" => destination_url})
    }

  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  rescue Populr::APIError => e
    halt JSON.generate({"error" => "An error occurred! #{e.message}"})
  end
end

private

def create_and_send_pop(template, data, delivery, user_email, user_phone)
  # First, create a new pop from the template
  p = Pop.new(template)

  # Assign it's title, slug, and other properties
  p.slug = data['slug']

  # Fill in {{tags}} in the body of the pop using the
  # values the user has provided in the pop_data parameter
  for tag,value in data['tags']
    p.populate_tag(tag, value)
  end

  # Fill in the regions that require files - image regions
  # and document regions. Our filepicker.io interface gives
  # us a URL to each file, and we need to create Populr assets
  # for each one. Each region on Populr can accept multiple
  # images / documents, so we allow for multiple selection.
  for region,urls in data['file_regions']
    assets = []
    for url in urls
      file = tempfile_for_url(url)
      name = url.split('/').last
      next unless file
      if p.type_of_unpopulated_region(region) == 'image'
          asset = @populr.images.build(file, name).save!
      elsif p.type_of_unpopulated_region(region) == 'document'
          asset = @populr.documents.build(file, name).save!
      end
      assets.push(asset)
    end
    p.populate_region(region, assets)
  end

  # Fill in embed regions by creating new embed assets with the
  # HTML the user provided. Each embed region should only have one
  # HTML asset in it, so this is more straightforward.
  for region,html in data['embed_regions']
    asset = @populr.embeds.build(html).save!
    p.populate_region(region, asset)
  end

  # As a sanity check, make sure we've filled all the regions and tags.
  # Populr won't let us publish a pop with unpopulated areas left in it!
  unless p.unpopulated_api_tags.count == 0 && p.unpopulated_api_regions.count == 0
    halt JSON.generate({"error" => "Please fill all of the tags and regions."})
  end

  # Save the pop. This commits our changes above.
  p.password = (0...5).map{(65+rand(26)).chr}.join if delivery['password']
  p.save!

  # Publish the pop. This makes it available at http://p.domain/p.slug.
  # The pop model is updated with a valid published_pop_url after this line!
  if delivery['action'] == 'publish'
    p.publish!

    if delivery['confirmation_email'] && user_email
      if delivery['password_sms'] && user_phone
        send_notification(user_email, {
          :instructions => t.delivery.email.publish_with_sms(user_phone),
          :url => p.published_pop_url,
          :password => nil
        })
        send_sms(user_phone, t.delivery.sms.password(p.password))
      else
        send_notification(user_email, {
          :instructions => t.delivery.email.publish,
          :url => p.published_pop_url,
          :password => p.password
        })
      end
    end
    yield p.published_pop_url, p

  elsif delivery['action'] == 'create'
    yield p._id, p

  elsif delivery['action'] == 'clone'
    p.enable_cloning!
    if delivery['confirmation_email'] && user_email
      send_notification(user_email, {
        :instructions => t.delivery.email.clone,
        :url => p.clone_link_url,
        :password => nil
      })
    end
    yield p.clone_link_url, p

  elsif delivery['action'] == 'collaborate'
    p.enable_collaboration!
    if delivery['confirmation_email'] && user_email
      send_notification(user_email, {
        :instructions => t.delivery.email.collaborate,
        :url => p.collaboration_link_url,
        :password => nil
      })
    end
    yield p.collaboration_link_url, p

  else
    return JSON.generate({"error" => "Invalid Embed Action"})
  end
end

def csv_template_headers(template)
  headers = ["Pop Slug"]
  for tag in template.api_tags
    headers << "#{tag}"
  end
  for region, info in template.api_regions
    headers << "#{region}"
  end
  headers << "Recipient Email"
  headers << "Recipient Phone"
  headers.to_csv
end

def tempfile_for_url(url)
  return unless url[0..3] == 'http'
  tempfile = Tempfile.new('filepicker')
  open(tempfile.path, 'w') do |f|
    f << open(url).read
  end
  tempfile
end

def send_notification(email, locals)
  rhtml = ERB.new(File.open("views/email.erb", "rb").read)
  Pony.mail(
    :to => email,
    :subject => 'Populate Notification',
    :headers => {'Content-Type' => 'text/html'},
    :body => rhtml.result(OpenStruct.new(locals).instance_eval { binding })
  )
  puts "Sent email #{email}:#{locals}"
end

def send_sms(phone, body)
  twillio = Twilio::REST::Client.new(ENV["TWILLIO_API_KEY"], ENV["TWILLIO_API_SECRET"])
  twillio.account.sms.messages.create(
    :from => '+15404405900',
    :to => phone,
    :body => body
  )
  puts "Sent SMS #{phone}:#{body}"
end

def sanitize_phone_number(phone)
  return nil unless phone
  phone = phone.gsub('-', '').gsub('.', '').gsub(' ', '')
  phone = '+1'+phone if phone[0..1] != '+1'
  phone
end

def url_for_environment_named(env)
  {
    "localhost"  => "http://api.lvh.me:3000",
    "staging"    => "https://api.populrstaging.com",
    "production" => "https://api.populr.me"
  }[env]
end

def collection_listing(collection)
  objects = []
  collection.each do |model|
    objects.push(model.as_json)
  end
  JSON.generate(objects)
end


