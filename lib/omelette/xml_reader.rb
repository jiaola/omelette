require 'nokogiri'

class Omelette::XmlReader
  attr_reader :settings, :folder

  def initialize(settings, file_paths)
    @settings = Omelette::Importer::Settings.new settings
    @file_paths = file_paths
  end

  def logger
    @logger ||= (@settings[:logger] || Yell.new(STDERR, :level => "gt.fatal"))
  end

  def each
    return enum_for(:each) unless block_given?
    @file_paths.each do |file|
      begin
        xml_doc = Nokogiri::XML(File.open(file))
        xml_doc.remove_namespaces! if settings['remove_xml_namespaces'].to_s == 'true'
        yield xml_doc, File.basename(file)
      rescue => ex
        self.logger.error "Problem processing file #{file}: #{ex.message}"
      end
    end
  end
end