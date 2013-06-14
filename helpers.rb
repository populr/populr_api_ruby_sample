
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
    yield p.published_pop_url, p

  elsif delivery['action'] == 'create'
    yield p.edit_url, p

  elsif delivery['action'] == 'clone'
    p.enable_cloning!
    if delivery['send_to_user'] && user_email
      send_notification(user_email, {
        :instructions => t.delivery.email.clone,
        :url => p.clone_link_url,
        :password => nil
      })
    end
    yield p.clone_link_url, p

  elsif delivery['action'] == 'collaborate'
    p.enable_collaboration!
    if delivery['send_to_user'] && user_email
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

def tempfile_for_url(url)
  return unless url[0..3] == 'http'
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