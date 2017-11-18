# A Null writer that does absolutely nothing with records given to it,
# just drops em on the floor.
class Omelette::NullWriter
  def initialize(_arg_settings)
  end


  def serialize(_context)
    # null
  end

  def put(_context)
    # null
  end

  def close
    # null
  end

end