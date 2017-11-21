module Omelette::Macros
  module Xpath
    def extract_xpath(xpath, namespaces={})
      lambda do |item, accumulator|
        nodes = item.xpath xpath, namespaces
        nodes.each do |node|
          accumulator << node.to_s.strip
        end
      end
    end
    module_function :extract_xpath
  end
end