class Omelette::Importer

  class ToItemTypeStep
    attr_accessor :item_type_name, :item_type_id, :block, :source_location, :item_type_map

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
      "(to_item_type #{@item_type_name} at #{@source_location})"
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
      item = { element_texts: [], item_type: {id: item_type_id}, public: true, featured: false }
      @import_steps.each do |import_step|
        break if context.skip?
        context.import_step = import_step
        result = Omelette::Util.log_mapping_errors context, import_step do
          import_step.execute context
        end
        begin
          if import_step.is_a? ToElementStep
            add_elements_to_item(result, item)
          else
            add_field_to_item(result, item)
          end
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

    def to_field(name, aLambda = nil, &block)
      if name == 'collection'
        @import_steps << ToCollectionStep.new(name, aLambda, block,Omelette::Util.extract_caller_location(caller.first))
      else
        @import_steps << ToFieldStep.new(name, aLambda, block,Omelette::Util.extract_caller_location(caller.first))
      end

    end

    def add_elements_to_item(elements, item)
      return if elements.empty?
      item[:element_texts].concat elements
    end

    def add_field_to_item(field, item)
      return if field.empty?
      item.merge! field
    end
  end

  class ToFieldStep
    attr_reader :lambda
    def initialize(name, lambda, block, source_location)
      @name = name
      self.lambda = lambda
      @block = block
      @source_location = source_location
    end

    # Set the arity of the lambda expression just once, when we define it
    def lambda=(lam)
      @lambda_arity = 0 # assume
      return unless lam

      @lambda = lam
      if @lambda.is_a?(Proc)
        @lambda_arity = @lambda.arity
      else
        raise NamingError.new("argument to each_record must be a block/lambda, not a #{lam.class} #{self.inspect}")
      end
    end

    def inspect
      "(to #{@name} at #{@source_location})"
    end

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

  class ToCollectionStep < ToFieldStep
    def execute(context)
      accumulator = super(context)
      accumulator.map { |value| { id: value } }
    end
  end

  class ToElementStep < ToFieldStep
    attr_accessor :element_set_name, :element_id, :element_map

    def initialize(element_name, element_set_name, element_map, lambda, block, source_location)
      @element_set_name = element_set_name
      super(element_name, lambda, block, source_location)
      validate!
      @element_id = element_map[@element_set_name][@name]
    end

    def validate!
      if @name.nil? || !@name.is_a?(String) || @name.empty?
        raise NamingError.new("to_element requires the element name (as a string) as the first argument at #{@source_location}")
      end
      if @element_set_name.nil? || !@element_set_name.is_a?(String) || @element_set_name.empty?
        raise NamingError.new("to_element requires the element set name (as a string) as the second argument at #{@source_location}")
      end

      [@lambda, @block].each do |proc|
        if proc && (proc.arity < 2 || proc.arity > 3)
          raise ArityError.new("error parsing element '#{@name}': block/proc given to to_element needs 2 or 3 (or variable) arguments #{proc}, (#{self.inspect})")
        end
      end
    end

    def to_element_step?
      true
    end

    def execute(context)
      accumulator = super(context)
      accumulator.map { |value|
        { html: false, element: {id: @element_id}, text: value }
      }
    end
  end
end