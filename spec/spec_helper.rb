require 'bundler/setup'
require 'omelette'
require 'webmock/rspec'

require 'omelette/importer/settings'
Omelette::Importer::Settings.defaults['log.level'] = 'gt.fatal'

def support_file_path(relative_path)
  return File.expand_path(File.join('spec_support', relative_path), File.dirname(__FILE__))
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.expose_dsl_globally = true

  config.before :all do
    @elements_data = IO.read(support_file_path 'elements.json')
    @element_sets_data = IO.read(support_file_path 'element_sets.json')
  end

  # WebMock reset after each example. Therefore we can't use it in before :all.
  config.before :all do
    stub_request(:get, /elements/).
        to_return(status: 200, body: @elements_data, headers: {})
    stub_request(:get, /element_sets/).
        to_return(status: 200, body: @element_sets_data, headers: {})
  end
end
