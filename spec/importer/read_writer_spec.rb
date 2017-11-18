require 'spec_helper'
require 'omelette/macros/xpath'
require 'omelette/xml_reader'

# A little Writer that just keeps everything
# in an array, just added to settings for easy access
memory_writer_class = Class.new do
  def initialize(settings)
    # store them in a class variable so we can test em later
    # Supress the warning message
    original_verbose, $VERBOSE = $VERBOSE, nil
    @@last_writer_settings = @settings = settings
    # Activate warning messages again.
    $VERBOSE = original_verbose
    @settings['memory_writer.added'] = []
  end

  def put(hash)
    @settings['memory_writer.added'] << hash
  end

  def close
    @settings['memory_writer.closed'] = true
  end
end

describe Omelette::Importer do
  before(:each) do
    @importer = Omelette::Importer.new('processing_thread_pool' => nil)
    @importer.writer_class = memory_writer_class
    @files = [ support_file_path('person_tei.xml') ]
    @importer.settings['omeka_api_root'] = 'www.example.com'
    @importer.settings['reader_class_name'] = 'Omelette::XmlReader'
  end

  describe '#process' do
    it 'works' do
      @importer.instance_eval do
        to_element 'Birth Date', 'Item Type Metadata', Omelette::Macros::Xpath.extract_xpath('//tei:particDesc/tei:person/tei:birth/@when')
      end
      result = @importer.process @files
      expect(result).to be true
    end
  end
end