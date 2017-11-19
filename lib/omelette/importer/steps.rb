class Omelette::Importer
  class ToItemTypeStep
    attr_accessor :item_type_name, :item_type_id, :block, :source_location, :item_type_map
    attr_reader :logger
    def initialize(item_type_name, opts, source_location, name_id_maps, &block)
      @item_type_name = item_type_name
      @import_steps = []
      @if_eval = opts[:if] if opts.has_key? :if
      @source_location = source_location
      @name_id_maps = name_id_maps
      validate!

      @item_type_id = @name_id_maps[:item_types][@item_type_name]
      instance_eval &block
    end

    def to_element_step?
      false
    end

    def to_item_type_step?
      true
    end

    def validate!
    end

    def inspect
      "(to_item_type #{self.item_type_name} at #{self.source_location})"
    end

    def can_process?(id)
      return true if @if_eval.nil?
      if @if_eval.is_a?(Symbol) or @if_eval.is_a?(String)
        return send(@if_eval, id)
      elsif @if_eval.lambda?
        return @if_eval.call(id)
      else
        # TODO: log invalid if_eval
        return false
      end
    end

    def execute(context)
      item = { element_texts: [], item_type: {id: item_type_id} }
      @import_steps.each do |import_step|
        break if context.skip?
        context.import_step = import_step
        elements = Omelette::Util.log_mapping_errors context, import_step do
          import_step.execute context
        end
        begin
          add_elements_to_item!(elements, item) if import_step.to_element_step?
        rescue NameError => ex
          msg = 'Tried to call add_element_to_item with a non-to_element step'
          msg += context.import_step.inspect
          context.logger.error msg
          raise ArgumentError.new msg
        end

        context.import_step = nil
      end
      return item
    end

    def to_element(element_name, element_set_name, aLambda = nil, &block)
      @import_steps << ToElementStep.new(element_name, element_set_name, @name_id_maps[:elements], aLambda, block, Omelette::Util.extract_caller_location(caller.first))
    end

    # Add the accumulator to the context with the correct field name
    # Do post-processing on the accumulator (remove nil values, allow empty
    # fields, etc)
    #
    # Only get here if we've got a to_field step; otherwise the
    # call to get a field_name will throw an error

    ALLOW_NIL_VALUES       = 'allow_nil_values'.freeze
    ALLOW_EMPTY_FIELDS     = 'allow_empty_fields'.freeze
    ALLOW_DUPLICATE_VALUES = 'allow_duplicate_values'.freeze

    def add_elements_to_item!(elements, item)
      return if elements.empty?
      item[:element_texts].concat elements
    end

  end

  class ToElementStep
    attr_accessor :element_name, :element_set_name, :element_id, :block, :source_location, :element_map
    attr_reader :lambda

    def initialize(element_name, element_set_name, element_map, lambda, block, source_location)
      self.element_name = element_name
      self.element_set_name = element_set_name
      self.lambda = lambda
      self.block = block
      self.source_location = source_location
      validate!

      self.element_id = element_map[self.element_set_name][self.element_name]
    end

    def validate!
      if self.element_name.nil? || !self.element_name.is_a?(String) || self.element_name.empty?
        raise NamingError.new("to_element requires the element name (as a string) as the first argument at #{self.source_location}")
      end
      if self.element_set_name.nil? || !self.element_set_name.is_a?(String) || self.element_set_name.empty?
        raise NamingError.new("to_element requires the element set name (as a string) as the second argument at #{self.source_location}")
      end

      [self.lambda, self.block].each do |proc|
        if proc && (proc.arity < 2 || proc.arity > 3)
          raise ArityError.new("error parsing element '#{element_name}': block/proc given to to_element needs 2 or 3 (or variable) arguments #{proc}, (#{self.inspect})")
        end
      end
    end

    def to_element_step?
      true
    end

    def lambda=(lam)
      @lambda       = lam
      @lambda_arity = @lambda ? @lambda.arity : 0
    end

    def inspect
      "(to_element #{self.element_name} at #{self.source_location})"
    end

    # to_element ""
    def execute(context)
      accumulator = []
      item = context.source_item
      if @lambda
        if @lambda_arity == 2
          @lambda.call item, accumulator
        else
          @lambda.call item, accumulator, context
        end
      end

      if @block
        @block.call(item, accumulator, context)
      end

      return accumulator
    end
  end
end