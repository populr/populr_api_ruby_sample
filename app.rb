require 'populr'
require 'json'
require 'open-uri'

register Sinatra::Reloader

set :public_folder, File.dirname(__FILE__) + '/public'

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


