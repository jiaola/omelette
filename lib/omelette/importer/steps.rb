class Omelette::Importer
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