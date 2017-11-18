# Write to Omeka using the API.
class Omelette::OmekaJsonWriter
  attr_reader :settings, :thread_pool_size
  attr_reader :batched_queue

  def initialize(arg_settings)
    @settings = Omelette::Importer::Settings.new arg_settings
  end
end