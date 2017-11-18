module Omelette::Macros
  module Xpath
    def extract_xpath(xpath, options={})
      options[:html] = false unless options.has_key? :html
      lambda do |item, elements, context|
        nodes = item.xpath xpath
        nodes.map { |node|
          elements << { html: options[:html], element: { id: context.import_step.element_id }, text: node.to_s.strip }
        }
      end
    end
    module_function :extract_xpath
  end
end