require 'rubygems'
require 'json'
require 'erb'
require 'csv'


if ENV['DOMAIN'][0..4] == 'https'
  require 'rack/ssl'
  use Rack::SSL
end

set :public_folder, File.dirname(__FILE__) + '/public'
set :frame_options, "ALLOW *"
set :protection, :except => :frame_options
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
  csv = csv_template_headers(template).to_csv

  response.headers['content_type'] = "text/csv"
  attachment("#{template.name} Template.csv")
  response.write(csv)
end

post "/_/templates/:template_id/csv" do
  find_api_connection
  template = @populr.templates.find(params[:template_id])

  job = PopCreationJob.new(
    :api_key => params[:api_key],
    :api_env => params[:api_env],
    :email => params[:email],
    :template_id => params[:template_id]
  )
  job.delivery_config = {
      'action' => params[:delivery_action],
      'password' => params[:delivery_passwords] != nil,
      'password_sms' => params[:delivery_two_factor_passwords] != nil,
      'send_to_user' => params[:delivery_send_to_user]
  }

  csv = params['file'][:tempfile].read
  csv_lines = csv.gsub("\r", "\n").gsub("\n\n", "\n").split("\n")

  # ensure that the first row of the CSV file hasn't been tampered with
  expected_headers = csv_template_headers(template)
  actual_headers = csv_lines[0]

  if expected_headers == actual_headers.parse_csv
    job.create_rows!(csv_lines[1..-1])
    job.create_resque_tasks
    redirect('/thanks.html')
  else
    halt("Make sure the first row of your CSV file matches the template! The first row should have the following columns: #{expected_headers}")
  end
end

get "/job_results/:job/:job_hash" do
  job = PopCreationJob.find(params[:job])
  return halt("Hash doesn't match.") unless job.hash == params[:job_hash]
  populr = Populr.new(job.api_key, url_for_environment_named(job.api_env))
  template = populr.templates.find(job.template_id)

  csv = csv_template_headers(template) + ["Success", "Result", "Password"]
  csv = csv.to_csv
  job.rows.each do |row|
    csv += (row.columns + row.output).to_csv
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

get "/_/pops/csv" do
  find_api_connection
  begin
    if params[:template_id]
      pops = @populr.templates.find(params[:template_id]).pops
    else
      pops = @populr.pops
    end
    csv = ['Creation Date', 'Pop ID', 'Pop Name', 'Title', 'Slug', 'Password', 'View URL', 'Edit URL', 'Publish Settings URL'].to_csv
    pops.each do |pop|
      publish_settings_url = "https://populr.me/pops/#{pop._id}/publish_settings"
      csv += [pop.created_at.to_s, pop._id, pop.name, pop.title, pop.slug, pop.password, pop.published_pop_url, pop.edit_url, publish_settings_url].to_csv
    end
    response.headers['content_type'] = "text/csv"
    attachment("Pops.csv")
    response.write(csv)
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
    'send_to_user' => params[:confirmation],
    'post_delivery_url' => params[:post_delivery_url]
  }

  properties = {
    :api_key => params[:api_key],
    :api_env => params[:api_env],
    :template_id => params[:template_id],
    :creator_email => params[:creator_email],
    :creator_notification => params[:creator_notification],
    :delivery_config => delivery_config
  }
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

    if data['slug'].nil? || data['slug'].empty?
      slug_components = [Time.new.to_i]
      slug_components << params[:pop_data]['tags']['title'] || params[:pop_data]['tags']['Title'] || nil
      data['slug'] = slug_components.compact.join('-')
    end

    create_and_send_pop(@template, data, @embed.delivery_config, user_email, user_phone) { |pop_url, pop|
      if @embed.creator_notification && @embed.creator_email
        send_notification(@embed.creator_email, {
          :instructions => t.embed.pop_created_notification(pop.name),
          :url => pop.edit_url,
          :password => nil
        })
      end

      next_url = @embed.delivery_config['post_delivery_url']
      next_url = pop_url if next_url.nil? || next_url.empty?
      return JSON.generate({"redirect_url" => next_url})
    }

  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  rescue Populr::APIError => e
    halt JSON.generate({"error" => "An error occurred! #{e.message}"})
  end
end

private



def csv_template_headers(template)
  headers = ["Pop Slug", "Pop Password"]
  for tag in template.api_tags
    headers << "#{tag}"
  end
  for region, info in template.api_regions
    headers << "#{region}"
  end
  headers << "Recipient Email"
  headers << "Recipient Phone"
  headers
end

def collection_listing(collection)
  objects = []
  collection.each do |model|
    objects.push(model.as_json)
  end
  JSON.generate(objects)
end


