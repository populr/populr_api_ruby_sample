require 'mongoid'

class PopDeliveryConfiguration
  include Mongoid::Document
  field :api_key, :type => String
  field :api_env, :type => String
  field :template_id, :type => String
  field :delivery_config, :type => Hash
end