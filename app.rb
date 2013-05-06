require 'rubygems'
require 'populr'
require 'json'
require 'open-uri'
require 'twilio-ruby'
require 'mongoid'
require 'pony'
require 'erb'
require 'ostruct'

class EmbedRecord
  include Mongoid::Document
  field :api_key
  field :api_environment
  field :template_id
  field :action
  field :confirmation
  field :password_sms_enabled
  field :password_enabled
end

class PopCreationJob
  include Mongoid::Document
  field :api_key
  field :api_environment
  field :template_id
  field :queued_rows, :type => Array, :default => []
  field :finished_rows_status, :type => Array, :default => []
  field :failed_row_count, :type => Integer, :default => 0
  field :delivery_action, :default => 'publish'
  field :delivery_passwords, :default => false
  field :delivery_two_factor_passwords, :default => false
  field :finished, :default => false
  field :email
end

Thread.new do
  while true do
    job = PopCreationJob.where(:finished => false).first
    unless job
      puts 'no job'
      sleep 1
      next
    end

    delivery = {
      :action => 'publish',
      :password => job.delivery_passwords,
      :password_sms => job.delivery_two_factor_passwords,
      :confirmation_email => true
    }

    begin
      @populr = Populr.new(job.api_key, environments[job.api_environment])
      @template = @populr.templates.find(job.template_id)

      for row in job.queued_rows
        data = {'file_regions' => {}, 'tags' => {}, 'embed_regions' => {}}
        values = row.split(',')
        vindex = 0

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
            data['file_regions'][region].push(values[vindex])
          end
          vindex += 1
        end
        user_email = values[vindex]
        user_phone = values[vindex+1]

        puts "processing row: #{row.to_json}"
        begin
          create_and_send_pop(@template, data, delivery, user_email, user_phone) { |destination_url, pop|
            job.finished_rows_status.push(['true', destination_url, pop.password])
            return JSON.generate({"redirect_url" => destination_url})
          }
        rescue Exception => e
          job.finished_rows_status.push(['false', "\"#{e.to_s}\"", ''])
          job.failed_row_count += 1
        end
      end


    rescue Exception => e
      send_notification(job.email, {
        :instructions => "Your job could not be processed successfully. Popul8 produced the error #{e.to_s}",
        :url => '',
        :password => nil
      })
    else
      send_notification(job.email, {
        :instructions => "Your job has been completed successfully. There were #{job.failed_row_count} failures. Click the link below to view those rows.",
        :url => "http://populr8.com/job_results/#{job._id}",
        :password => nil
      })
    ensure
      job.finished = true
      job.save!
    end
  end
end


configure do
  Mongoid.configure do |config|
    config.sessions = {
      :default => {
        :hosts => ["localhost:27017"], :database => "my_db"
      }
    }
  end
  Pony.options = {
    :from => "noreply@popul8.me",
    :via => :smtp,
    :via_options => {
      :address => 'smtp.sendgrid.net',
      :port => '587',
      :authentication => :plain,
      :user_name => ENV['SENDGRID_USERNAME'],
      :password => ENV['SENDGRID_PASSWORD'],
      :domain => ENV['SENDGRID_DOMAIN'],
      :enable_starttls_auto => true
    },
  }
end

register Sinatra::Reloader

set :public_folder, File.dirname(__FILE__) + '/public'


before do
  if request.request_method == "POST"
    begin
    body_parameters = request.body.read
    params.merge!(JSON.parse(body_parameters))
    rescue
    end
  end
end


def environments
  {
  "localhost"  => "http://api.lvh.me:3000",
  "staging"    => "https://api.populrstaging.com",
  "production" => "https://api.populr.me"
  }
end

def find_api_connection
  @populr = Populr.new(params[:api_key], environments[params[:api_env]]) if params[:api_key]

  if params[:embed]
    @embed = EmbedRecord.find(params[:embed])
    @populr = Populr.new(@embed.api_key, environments[@embed.api_environment])
    @template = @populr.templates.find(@embed.template_id)
  end

  halt "API Key Required" if request.path.include?('_/') && !@populr
end


get "/" do
  redirect('/index.html')
end

post "/callback/tracer_viewed" do
  return unless ENV["TWILLIO_API_KEY"]
  clicks = params[:tracer]['analytics']['clicks'] if params[:tracer]['analytics']
  clicks ||= 0
  twillio = Twilio::REST::Client.new(ENV["TWILLIO_API_KEY"], ENV["TWILLIO_API_SECRET"])
  twillio.account.sms.messages.create(
    :from => ENV["TWILLIO_NUMBER"],
    :to => params[:tracer]['name'],
    :body => "Thanks for viewing your pop. You clicked #{clicks} items."
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
  find_api_connection
  begin
    return collection_listing(@populr.templates)
  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  end
end

get "/_/templates/:template_id/csv" do
  find_api_connection
  template = @populr.templates.find(template_id)
  csv = csv_template_headers(template)
  csv += "Recipient Email,Recipient Phone\n"

  response.headers['content_type'] = "text/csv"
  attachment("#{template.name} Template.csv")
  response.write(csv)
end

post "/_/templates/:template_id/csv" do
  find_api_connection
  template = @populr.templates.find(params[:template_id])

  job = PopCreationJob.new(:api_key => params[:api_key], :api_environment => params[:api_env])
  job.template_id = params[:template_id]
  job.delivery_action = params[:delivery_action]
  job.delivery_passwords = params[:delivery_passwords]
  job.delivery_two_factor_passwords = params[:delivery_two_factor_passwords]

  csv = params['file'][:tempfile].read
  job.queued_rows = csv.split("\r")[1..-1]
  job.email = params[:email]
  job.save!

  redirect('/index.html')
end

get "/job_results/:job" do
  job = PopCreationJob.find(params[:job])
  populr = Populr.new(job.api_key, environments[job.api_environment])
  template = populr.templates.find(job.template_id)

  csv = csv_template_headers(template) + "Success,URL,Password\r"
  job.queued_rows.count.times do |i|
    csv += job.queued_rows[i] + ',' + job.finished_rows_status[i].join(',') + "\r"
  end
  response.headers['content_type'] = "text/csv"
  attachment("Failed Rows.csv")
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
  properties = {:api_key => params[:api_key], :api_environment => params[:api_env], :template_id => params[:template_id], :action => params[:action], :confirmation => params[:confirmation], :password_enabled => params[:password_enabled], :password_sms_enabled => params[:password_sms_enabled]}
  embed = EmbedRecord.where(properties).first
  if !embed
    embed = EmbedRecord.new(properties)
    embed.save!
  end
  return embed.to_json if embed
end


post "/_/embeds/:embed/build_pop" do
  find_api_connection
  begin
    return "Template Not Found" unless @template

    user_email = params[:pop_data]['popul8_recipient_email']
    user_phone = sanitize_phone_number(params[:pop_data]['popul8_recipient_phone'])
    data = params[:pop_data]
    delivery = {
      :action => @embed.action,
      :password => @embed.password,
      :password_sms => @embed.password_sms_enabled,
      :confirmation_email => @embed.confirmation
    }

    create_and_send_pop(@template, data, delivery, user_email, user_phone) { |destination_url|
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
  p = Pop.new(@template)

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
      next unless file
      if p.type_of_unpopulated_region(region) == 'image'
          asset = @populr.images.build(file, 'Filepicker Image').save!
      elsif p.type_of_unpopulated_region(region) == 'document'
          asset = @populr.documents.build(file, 'Filepicker Document').save!
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
  p.password = (0...5).map{(65+rand(26)).chr}.join if delivery[:password]
  p.save!

  # Publish the pop. This makes it available at http://p.domain/p.slug.
  # The pop model is updated with a valid published_pop_url after this line!
  if delivery[:action] == 'publish'
    p.publish!

    if delivery[:confirmation_email]
      if delivery[:password_sms]
        send_notification(user_email, {
          :instructions => "Click the link below to view your page. For security, you'll need to enter a password which was sent to your mobile phone (#{user_phone}) in a text message.",
          :url => p.published_pop_url,
          :password => nil
        })
        twillio = Twilio::REST::Client.new(ENV["TWILLIO_API_KEY"], ENV["TWILLIO_API_SECRET"])
        twillio.account.sms.messages.create(
          :from => '+15404405900',
          :to => user_phone,
          :body => "POP POP! The password for your new pop is #{p.password}."
        )
      else
        send_notification(user_email, {
          :instructions => "Click the link below to view your page.",
          :url => p.published_pop_url,
          :password => p.password
        })
      end
    end
    yield p.published_pop_url, p

  elsif delivery[:action] == 'clone'
    p.enable_cloning!
    if delivery[:confirmation_email]
      send_notification(user_email, {
        :instructions => 'Click the link below and follow the instructions to create a Populr.me account and continue editing your new page!',
        :url => p.clone_link_url,
        :password => nil
      })
    end
    yield p.clone_link_url, p

  elsif delivery[:action] == 'collaborate'
    p.enable_collaboration!
    if delivery[:confirmation_email]
      send_notification(user_email, {
        :instructions => 'Click the link below and follow the instructions to create a Populr.me account and customize your new page!',
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
  csv = ""
  for tag in template.api_tags
    csv += "#{tag},"
  end
  for region, info in template.api_regions
    csv += "#{region},"
  end
  csv
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
    :subject => 'Your Pop!',
    :headers => {'Content-Type' => 'text/html'},
    :body => rhtml.result(OpenStruct.new(locals).instance_eval { binding })
  )
end


def sanitize_phone_number(phone)
  return nil unless phone
  phone = phone.gsub('-', '').gsub('.', '').gsub(' ', '')
  phone = '+1'+phone if phone[0..1] != '+1'
  phone
end

def collection_listing(collection)
  objects = []
  collection.each do |model|
    objects.push(model.as_json)
  end
  JSON.generate(objects)
end


