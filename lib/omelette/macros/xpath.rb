module Omelette::Macros
  module Xpath
    def extract_xpath(xpath, options={})
      options[:html] = false unless options.has_key? :html
      lambda do |item, accumulator|
        nodes = item.xpath xpath, tei: 'http://www.tei-c.org/ns/1.0'
        nodes.each do |node|
          accumulator << node.to_s.strip
        end
      end
    end
    module_function :extract_xpath
  end
end