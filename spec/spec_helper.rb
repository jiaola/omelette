require 'bundler/setup'
require 'omelette'
require 'webmock/rspec'

require 'omelette/importer/settings'
Omelette::Importer::Settings.defaults['log.level'] = 'gt.fatal'

include Omelette::Macros::Xpath

def file_fixture(relative_path)
  return Pathname.new(File.expand_path(File.join('fixtures', relative_path), File.dirname(__FILE__)))
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
    @elements_data = file_fixture('elements.json').read
    @element_sets_data = file_fixture('element_sets.json').read
    @item_types_data = file_fixture('item_types.json').read
  end

  # WebMock reset after each example. Therefore we can't use it in before :all.
  config.before :each do
    allow(Omelette::Util).to receive(:build_collections_map).and_return({'CWGK Organization' => 1, 'CWGK Person' => 2 })
    allow(Omelette::Util).to receive(:build_items_map).and_return({'N00000247' => 200})
    stub_request(:get, /elements/).
        to_return(status: 200, body: @elements_data, headers: {})
    stub_request(:get, /element_sets/).
        to_return(status: 200, body: @element_sets_data, headers: {})
    stub_request(:get, /item_types/).
        to_return(status: 200, body: @item_types_data, headers: {})
  end
end
