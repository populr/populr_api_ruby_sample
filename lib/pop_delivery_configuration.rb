require 'mongoid'

class PopDeliveryConfiguration
  include Mongoid::Document
  field :api_key
  field :api_env
  field :template_id
  field :delivery_config
end