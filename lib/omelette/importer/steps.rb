class Omelette::Importer

  class ToItemTypeStep
    attr_accessor :item_type_name, :block, :source_location, :item_type_map

    def initialize(item_type_name, opts, source_location, &block)
      @item_type_name = item_type_name
      @map_steps = []
      @if_eval = opts[:if] if opts.has_key? :if
      @source_location = source_location
      validate!

      instance_eval &block if block_given?
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
      begin
        item_type_id = context.mappings[:item_types][@item_type_name]
      rescue KeyError => ex
        msg = "Failed to map the item type name: #{@item_type_name} to an identifier. "
        context.logger.error msg
        raise ArgumentError.new msg
      end

      item = { element_texts: [], item_type: { id: item_type_id }, public: true, featured: false }
      @map_steps.each do |map_step|
        break if context.skip?
        context.map_step = map_step
        values = Omelette::Util.log_mapping_errors context, map_step do
          map_step.execute context
        end
        begin
          add_to_item(map_step.name, values, item)
        rescue NameError => ex
          msg = 'Tried to call add_to_item with a non-to_element step'
          msg += context.map_step.inspect
          context.logger.error msg
          raise ArgumentError.new msg
        end

        context.map_step = nil
      end
      return item
    end

    def to_element(element_name, element_set_name, aLambda = nil, &block)
      @map_steps << ToElementStep.new(element_name, element_set_name,aLambda, block, Omelette::Util.extract_caller_location(caller.first))
    end

    def to_field(name, aLambda = nil, &block)
      if name == 'collection'
        @map_steps << ToCollectionStep.new(name, aLambda, block,Omelette::Util.extract_caller_location(caller.first))
      else
        @map_steps << ToFieldStep.new(name, aLambda, block,Omelette::Util.extract_caller_location(caller.first))
      end

    end

    # Only :tag and :element_texts are multi-value fields
    def add_to_item(name, values, item)
      name = name.to_sym
      if name == :tags or name == :element_texts
        item[name] = item.fetch(name, []).concat values
      else
        item[name] = values[-1]
      end
    end
  end

  class LambdaBlockStep
    attr_accessor :name, :source_location
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

  class ToFieldStep < LambdaBlockStep
  end

  class ToCollectionStep < LambdaBlockStep
    def execute(context)
      accumulator = super(context)
      accumulator.map { |value| { id: value } }
    end
  end

  class ToElementStep < LambdaBlockStep
    attr_accessor :element_set_name, :element_name

    def initialize(element_name, element_set_name, lambda, block, source_location)
      @element_set_name = element_set_name
      @element_name = element_name
      super('element_texts', lambda, block, source_location)
      validate!
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

    def execute(context)
      begin
        element_id = context.mappings[:elements][@element_set_name][@name] rescue nil
      rescue KeyError => ex
        msg = "Failed to map the element name: #{@name} and element set: #{@element_set_name} to an identifier. "
        context.logger.error msg
        raise ArgumentError.new msg
      end

      accumulator = super(context)
      accumulator.map { |value|
        { html: false, element: {id: element_id}, text: value }
      }
    end
  end
end