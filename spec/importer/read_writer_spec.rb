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
    @files = [ file_fixture('person_tei.xml').to_s, file_fixture('organization_tei.xml').to_s ]
    @importer.settings['omeka_api_root'] = 'http://www.example.com/api'
    @importer.settings['reader_class_name'] = 'Omelette::XmlReader'
    allow(@importer).to receive(:create_db_client).and_return(nil)
  end

  describe '#process' do
    it 'works' do
      @importer.instance_eval do
        to_item_type 'CWGK Person', if: lambda {|id| id.include? 'person'} do
          to_field 'identifier', extract_xpath('//tei:TEI/@xml:id') do |_item, accumulator|
            accumulator.map! {|x| x[1..-1]}
          end
          to_field 'collection', extract_xpath('//tei:teiHeader/tei:fileDesc/tei:sourceDesc/tei:msDesc/tei:msIdentifier/tei:collection/text()')
          to_element 'Birth Date', 'Item Type Metadata', extract_xpath('//tei:particDesc/tei:person/tei:birth/@when')
        end
        to_item_type 'CWGK Organization', if: lambda {|id| id.include? 'organization'} do
          to_field 'identifier', extract_xpath('//tei:TEI/@xml:id') do |_item, accumulator|
            accumulator.map {|x| x[1..-1]}
          end
          to_element 'Creation Date', 'Item Type Metadata', extract_xpath('//tei:particDesc/tei:org/tei:event[@type="begun"]/@when')
        end
      end
      result = @importer.process @files
      expect(result).to be true

      writer_settings = memory_writer_class.class_variable_get('@@last_writer_settings')
      expect(writer_settings['memory_writer.added']).not_to be nil
      expect(writer_settings['memory_writer.added'].length).to be 2
      expect(writer_settings['memory_writer.added'].first.output_item[:element_texts][0][:text]).to eq '1823'
      expect(writer_settings['logger']).not_to be nil
      expect(writer_settings['memory_writer.closed']).to be true
    end
  end
end