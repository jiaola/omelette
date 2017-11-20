# Represents the context of a specific item being imported, passed
# to importing logic blocks
#
class Omelette::Importer
  class Context
    def initialize(hash_init = {})
      # TODO, argument checking for required args?

      self.clipboard   = {}
      self.output_item = {}

      hash_init.each_pair do |key, value|
        self.send("#{key}=", value)
      end

      @skip = false
    end

    attr_accessor :clipboard, :output_item, :logger
    attr_accessor :import_step, :source_item, :settings, :source_item_id
    # 1-based position in stream of processed records.
    attr_accessor :position

    # Should we be skipping this record?
    attr_accessor :skipmessage

    # Set the fact that this record should be skipped, with an
    # optional message
    def skip!(msg = '(no message given)')
      @skipmessage = msg
      @skip        = true
    end

    # Should we skip this record?
    def skip?
      @skip
    end

    def item_type=(item_type)
      self.output_item[:item_type] = {id: item_type}
    end

    def item_type
      self.output_item.fetch(:item_type, {})[:id]
    end

    def collection=(collection)
      self.output_item[:collection] = {id: collection}
    end

    def collection
      self.output_item.fetch(:collection, {})[:id]
    end

    def add_elements(elements)
      self.output_item[:element_texts].concat elements
    end
  end

end
