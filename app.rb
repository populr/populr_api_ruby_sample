require 'populr'
require 'json'
require 'open-uri'
require 'twilio-ruby'

register Sinatra::Reloader

set :public_folder, File.dirname(__FILE__) + '/public'

twillio_api_key = nil
twillio_secret = nil

environments = {
  "localhost"  => "http://api.lvh.me:3000",
  "staging"    => "https://api.populrstaging.com",
  "production" => "https://api.populr.me"}


before do
  if request.request_method == "POST"
    body_parameters = request.body.read
    params.merge!(JSON.parse(body_parameters))
  end

  @populr = Populr.new(params[:api_key], environments[params[:api_env]]) if params[:api_key]
  halt "API Key Required" if request.path.include?('_/') && !@populr
end


get "/" do
  redirect('/index.html')
end

get "/_/templates" do
  begin
    return collection_listing(@populr.templates)
  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  end
end

post "/callback/tracer_viewed" do
  return unless twillio_api_key
  clicks = params[:tracer]['analytics']['clicks'] if params[:tracer]['analytics']
  clicks ||= 0
  twillio = Twilio::REST::Client.new(twillio_api_key, twillio_secret)
  twillio.account.sms.messages.create(
    :from => '+15404405900',
    :to => params[:tracer]['name'],
    :body => "Thanks for viewing your pop. You clicked #{clicks} items."
  )
end


get "/_/pops" do
  begin
    if params[:template_id]
      return collection_listing(@populr.templates.find(params[:template_id]).pops)
    else
      return collection_listing(@populr.pops)
    end

  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  end
end


post "/_/pops" do
  begin
    template = @populr.templates.find(params[:template_id])
    return "Template Not Found" unless template

    # First, create a new pop from the template
    p = Pop.new(template)

    # Assign it's title, slug, and other properties
    p.slug = params[:pop_data]['slug']

    # Fill in {{tags}} in the body of the pop using the
    # values the user has provided in the pop_data parameter
    for tag,value in params[:pop_data]['tags']
      p.populate_tag(tag, value)
    end

    # Fill in the regions that require files - image regions
    # and document regions. Our filepicker.io interface gives
    # us a URL to each file, and we need to create Populr assets
    # for each one. Each region on Populr can accept multiple
    # images / documents, so we allow for multiple selection.
    for region,urls in params[:pop_data]['file_regions']
      assets = []
      for url in urls
        file = tempfile_for_url(url)
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
    for region,html in params[:pop_data]['embed_regions']
      asset = @populr.embeds.build(html).save!
      p.populate_region(region, asset)
    end

    # As a sanity check, make sure we've filled all the regions and tags.
    # Populr won't let us publish a pop with unpopulated areas left in it!
    unless p.unpopulated_api_tags.count == 0 && p.unpopulated_api_regions.count == 0
      halt JSON.generate({"error" => "Please fill all of the tags and regions."})
    end

    # Save the pop. This commits our changes above.
    p.save!

    # Publish the pop. This makes it available at http://p.domain/p.slug.
    # The pop model is updated with a valid published_pop_url after this line!
    p.publish!

    # Has the user requested a tracer? If so, we've got some work to do...
    if (params[:pop_data]['tracer_phone'] && !params[:pop_data]['tracer_phone'].empty?)
      p.password = (0...5).map{(65+rand(26)).chr}.join
      p.save!


      number = params[:pop_data]['tracer_phone'].gsub('-', '').gsub('.', '').gsub(' ', '')
      number = '+1'+number if number[0..1] != '+1'

      tracer = p.tracers.build
      tracer.name = number
      tracer.enable_webhook('http://localhost:5000/callback/tracer_viewed')
      tracer.save!

      if twillio_api_key
        twillio = Twilio::REST::Client.new(twillio_api_key, twillio_secret)
        twillio.account.sms.messages.create(
          :from => '+15404405900',
          :to => number,
          :body => "POP POP! Visit #{p.published_pop_url}?#{tracer.code} to view #{p.title}. Use pass #{p.password}."
        )
      else
        puts "POP POP! Visit #{p.published_pop_url}?#{tracer.code} to view #{p.title}. Use pass #{p.password}."
      end
    end


    return JSON.generate(p.as_json)

  rescue Populr::AccessDenied
    halt JSON.generate({"error" => "API Key Rejected"})
  rescue Populr::APIError => e
    halt JSON.generate({"error" => "An error occurred! #{e.message}"})
  end
end


private

def tempfile_for_url(url)
  tempfile = Tempfile.new('filepicker')
  open(tempfile.path, 'w') do |f|
    f << open(url).read
  end
  tempfile
end

def collection_listing(collection)
  objects = []
  collection.each do |model|
    objects.push(model.as_json)
  end
  JSON.generate(objects)
end


