require 'populr'
require 'json'
require 'open-uri'

register Sinatra::Reloader

set :public_folder, File.dirname(__FILE__) + '/public'

before do
  if request.request_method == "POST"
    body_parameters = request.body.read
    params.merge!(JSON.parse(body_parameters))
  end
end

get "/_/templates" do
  begin
    return "API Key Required" unless params[:api_key]
    populr = Populr.new(params[:api_key])
    JSON.generate(populr.templates.as_json)
  rescue Populr::AccessDenied
    return JSON.generate({"error" => "API Key Rejected"})
  end
end

post "/_/pops" do
  begin
    puts params

    return "API Key Required" unless params[:api_key]
    return "Template ID Required" unless params[:template_id]

    populr = Populr.new(params[:api_key])
    template = populr.templates.find(params[:template_id])

    return "Template Not Found" unless template

    p = Pop.new(template)
    p.slug = params[:slug]
    for tag,value in params[:pop_data]['tags']
      p.populate_tag(tag, value)
    end

    for region,urls in params[:pop_data]['regions']
      assets = []
      for url in urls
        tempfile = Tempfile.new('filepicker')
        open(tempfile.path, 'w') do |f|
          f << open(url).read
        end
        asset = populr.images.build(tempfile, 'Filepicker File').save!
        assets.push(asset)
      end
      p.populate_region(region, assets)
    end

    if p.unpopulated_api_tags.count == 0 && p.unpopulated_api_regions.count == 0
      p.save!
      p.publish!
      return JSON.generate(p.as_json)
    else
      return JSON.generate({"error" => "Please fill all of the tags and regions."})
    end

  rescue Populr::AccessDenied
    return JSON.generate({"error" => "API Key Rejected"})
  rescue Populr::APIError => e
    return JSON.generate({"error" => "An error occurred! #{e.message}"})
  end
end


