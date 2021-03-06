require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module WorkOrders
  class Application < Rails::Application

    config.load_defaults 5.0

    config.generators do |g|
      g.test_framework :rspec,
                       fixtures: true,
                       view_specs: false,
                       helper_specs: false,
                       routing_specs: false,
                       controller_specs: false,
                       request_specs: true

      g.fixture_replacement :factory_bot, dir: 'spec/factories'

      g.assets false
    end

    config.assets.paths << Rails.root.join("vendor", "assets", "fonts")

    # These services/actions are mocked out in initializers when not enabled.
    config.ubw = { enabled: true }
    config.data_release_client = { enabled: true }
    config.send_to_lims = { enabled: true }

    config.dispatch_queue = {
      retry_interval: proc { |count| count ** 4 + 3 },
      maximum_retry_count: 10
    }

    config.ldap = config_for(:ldap)
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    config.eager_load_paths << Rails.root.join('lib')

    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*', :headers => :any, :methods => [:get, :put, :options]
      end
    end

    config.active_record.schema_format = :sql
  end
end
