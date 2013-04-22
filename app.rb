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

  if params[:api_key]
    if params[:api_env] == 'localhost'
      @populr = Populr.new(params[:api_key], "http://api.lvh.me:3000")
    elsif params[:api_env] == 'staging'
      @populr = Populr.new(params[:api_key], "https://api.populrstaging.com")
    elsif params[:api_env] == 'production'
      @populr = Populr.new(params[:api_key])
    else
      raise "Environment not set! Please choose one of the three options."
    end
  end

end

get "/" do
  redirect('/index.html')
end

get "/_/templates" do
  begin
    return "API Key Required" unless @populr
    objects = []
    @populr.templates.all.each do |model|
      objects.push(model.as_json)
    end
    JSON.generate(objects)
  rescue Populr::AccessDenied
    return JSON.generate({"error" => "API Key Rejected"})
  end
end

get "/_/pops" do
  begin
    return "API Key Required" unless @populr
    objects = []
    if params[:template_id]
      collection = @populr.templates.find(params[:template_id]).pops
    else
      collection = @populr.pops
    end

    collection.each do |model|
      objects.push(model.as_json)
    end
    JSON.generate(objects)

  rescue Populr::AccessDenied
    return JSON.generate({"error" => "API Key Rejected"})
  end
end


post "/_/pops" do
  begin
    return "API Key Required" unless @populr

    template = @populr.templates.find(params[:template_id])
    return "Template Not Found" unless template

    p = Pop.new(template)
    p.slug = params[:pop_data]['slug']
    for tag,value in params[:pop_data]['tags']
      p.populate_tag(tag, value)
    end

    for region,urls in params[:pop_data]['file_regions']
      assets = []
      for url in urls
        tempfile = Tempfile.new('filepicker')
        open(tempfile.path, 'w') do |f|
          f << open(url).read
        end

        if p.type_of_unpopulated_region(region) == 'image'
          asset = @populr.images.build(tempfile, 'Filepicker Image').save!
        elsif p.type_of_unpopulated_region(region) == 'document'
          asset = @populr.documents.build(tempfile, 'Filepicker File').save!
        end
        assets.push(asset)
      end
      p.populate_region(region, assets)
    end

    for region,html in params[:pop_data]['embed_regions']
      asset = @populr.embeds.build(html).save!
      p.populate_region(region, asset)
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


