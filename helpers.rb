
def url_for_environment_named(env)
  {
    "localhost"  => "http://api.lvh.me:3000",
    "staging"    => "https://api.populrstaging.com",
    "production" => "https://api.populr.me"
  }[env]
end

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
  url_to_asset_id_map = {}
  for region,urls in data['file_regions']
    assets = []
    for url in urls
      file = tempfile_for_url(url)
      name = URI.decode(url.split('/').last)
      name = name[0..name.rindex('.')-1] if name.rindex('.')

      next unless file
      if p.type_of_unpopulated_region(region) == 'image'
        asset = @populr.images.build(file, name).save!
      elsif p.type_of_unpopulated_region(region) == 'document'
        asset = @populr.documents.build(file, name).save!
      end

      url_to_asset_id_map[url] = asset._id

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


  # Save the pop. This commits our changes above.
  if delivery['password']
    p.password = data['password']
    p.password ||= (0...5).map{(65+rand(26)).chr}.join
  end

  p.save!

  # Publish the pop. This makes it available at http://p.domain/p.slug.
  # The pop model is updated with a valid published_pop_url after this line!
  if delivery['action'] == 'publish'
    p.publish!

    if delivery['send_to_user'] && user_email
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
    yield p.published_pop_url, p, url_to_asset_id_map

  elsif delivery['action'] == 'create'
    yield p.edit_url, p, url_to_asset_id_map

  elsif delivery['action'] == 'clone'
    p.enable_cloning!
    if delivery['send_to_user'] && user_email
      send_notification(user_email, {
        :instructions => t.delivery.email.clone,
        :url => p.clone_link_url,
        :password => nil
      })
    end
    yield p.clone_link_url, p, url_to_asset_id_map

  elsif delivery['action'] == 'collaborate'
    p.enable_collaboration!
    if delivery['send_to_user'] && user_email
      send_notification(user_email, {
        :instructions => t.delivery.email.collaborate,
        :url => p.collaboration_link_url,
        :password => nil
      })
    end
    yield p.collaboration_link_url, p, url_to_asset_id_map

  else
    return JSON.generate({"error" => "Invalid Embed Action"})
  end
rescue Populr::UnexpectedResponse, Populr::APIError => e
  puts e.to_s
  p.destroy if p
  raise e
end

def strip_whitespace(columns)
  # remove any whitespace in the cells. We have to do this because some version of Excel
  # is changing the columns from "Pop Password,Pop Slug" to "Pop Password, Pop Slug"
  for column in columns
    column.strip! unless column.blank?
  end
end

def tempfile_for_url(url)
  return unless url[0..3] == 'http'

  # make sure all uris are escaped, even if they're not in the excel file
  url = URI.escape(URI.unescape(url))
  tempfile = Tempfile.new(['filepicker', File.extname(url)])
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

def state_columns
  ['Edit URL', 'Publish Settings URL', 'Analytics URL', 'Views', 'Clicks'].concat(@assets)
end

def state_values_for_pop(populr, pop_id, column_headers=[], asset_id_to_column_index_map={})
  @assets ||= []
  return [] unless pop_id && populr

  publish_settings_url = "https://populr.me/pops/#{pop_id}/publish_settings"
  analytics_url = "https://populr.me/pops/#{pop_id}/analytics"

  pop = Pop.new(populr)
  pop._id = pop_id
  analytics = pop.analytics

  asset_clicks = []

  if analytics['direct_tracer'] && analytics['direct_tracer']['analytics']
    direct_tracer_analytics = analytics['direct_tracer']['analytics']
    direct_tracer_analytics.keys.each do |key|
      id, kind = key.split(':')

      if kind == 'c'
        clicks = direct_tracer_analytics[id + ':c']
        url = direct_tracer_analytics[id + ':u']
        name = direct_tracer_analytics[id + ':n']
        header = matching_column_name(column_headers, asset_id_to_column_index_map, name, url)

        if index = @assets.index(header)
          asset_clicks[index] = clicks
        else
          @assets << header
          asset_clicks << clicks
        end

      end
    end
  end

  [pop.edit_url, publish_settings_url, analytics_url, analytics['views'], analytics['clicks']].concat(asset_clicks)
rescue Populr::ResourceNotFound
  false
end

def matching_column_name(column_headers, asset_id_to_column_index_map, asset_name, asset_url)
  if asset_url
    uri = URI.parse(asset_url)
    asset_id = File.basename(uri.path, '.*')
    column_index = asset_id_to_column_index_map[asset_id]
  else
    column_index = nil
  end

  'Asset Clicks: ' +  if column_index
                        column_headers[column_index]

                      elsif asset_name.nil? || asset_url.nil?
                        "#{asset_name}#{asset_url}"

                      else
                        "#{asset_name} | #{asset_url}"
                      end
end
