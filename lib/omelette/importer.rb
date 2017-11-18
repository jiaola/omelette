require 'yell'
require 'omelette/importer/context'
require 'omelette/importer/settings'
require 'omelette/importer/errors'
require 'omelette/importer/steps'
require 'omelette/thread_pool'
require 'omelette/macros/xpath'

class Omelette::Importer
  include Omelette::Macros::Xpath

  attr_writer :reader_class, :writer_class, :writer
  attr_reader :logger

  def initialize(arg_settings = {})
    @settings = Settings.new(arg_settings)
    @import_steps = []
    @after_processing_steps = []

    @logger = create_logger
  end

  def elements_map
    @elements_map ||= Omelette::Util.build_elements_map @settings['omeka_api_root']
  end

  # Pass a string file path, a Pathname, or a File object, for
  # a config file to load into indexer.
  #
  # Can raise:
  # * Errno::ENOENT or Errno::EACCES if file path is not accessible
  # * Omelette::Importer::ConfigLoadError if exception is raised evaluating
  #   the config. A ConfigLoadError has information in it about original
  #   exception, and exactly what config file and line number triggered it.
  def load_config_file(file_path)
    File.open file_path do |file|
      begin
        self.instance_eval file.read, file_path.to_s
      rescue ScriptError, StandardError => ex
        raise ConfigLoadError.new(file_path.to_s, ex)
      end
    end
  end

  def settings(new_settings = nil, &block)
    @settings.merge! new_settings if new_settings
    @settings.instance_eval &block if block_given?
    return @settings
  end

  def to_item_type(item_type_name, aLambda = nil, &block)

  end

  def to_element(element_name, element_set_name, aLambda = nil, &block)
    @import_steps << ToElementStep.new(element_name, element_set_name, elements_map, aLambda, block, Omelette::Util.extract_caller_location(caller.first))
  end

  # Processes a single item according to extracting rules set up in
  # this importer. Returns the output hash (a hash whose keys are
  # string fields, and values are arrays of one or more values in that field)
  #
  # This is a convenience shortcut for #map_to_context! -- use that one
  # if you want to provide addtional context
  # like position, and/or get back the full context.
  def map_item(item)
    context = Context.new(source_item: item, settings: settings)
    map_to_context! context
    return context.output_hash
  end

  def map_to_context!(context)
    @import_steps.each do |import_step|
      break if context.skip?

      # set the to_element step for error reporting
      context.import_step = import_step
      elements = log_mapping_errors context, import_step do
        import_step.execute context
      end
      add_elements_to_context!(elements, context) if import_step.to_element_step?

      # Unset the import step after it's finished
      context.import_step = nil
    end
    return context
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

  def add_elements_to_context!(elements, context)
    elements.compact! unless settings[ALLOW_NIL_VALUES]
    return if elements.empty? and not (settings[ALLOW_EMPTY_FIELDS])

    context.add_elements elements
    #existing_element.uniq! unless settings[ALLOW_DUPLICATE_VALUES]

  rescue NameError => ex
    msg = 'Tried to call add_element_to_context with a non-to_element step'
    msg += context.import_step.inspect
    logger.error msg
    raise ArgumentError.new msg
  end

  def process(files)
    settings.fill_in_defaults!

    count = 0
    start_time = batch_start_time = Time.now
    logger.debug "beginning Omelette::Import*process with settings: #{settings.inspect}"
    reader = self.reader! files
    processing_threads = settings['processing_thread_pool'].to_i
    thread_pool = Omelette::ThreadPool.new processing_threads

    logger.info "   Importer with #{processing_threads} processing threads, reader: #{reader.class.name} and writer: #{writer.class.name}"
    log_batch_size = settings['log.batch_size'] && settings['log.batch_size'].to_i

    reader.each do |item, item_id; position|
      count += 1
      position = count

      thread_pool.raise_collected_exception!

      if settings['debug_ascii_progress'].to_s == 'true'
        $stderr.write '.' if count % settings['solr_writer.batch_size'].to_i == 0
      end

      context = Context.new source_item: item, source_item_id: item_id, settings: settings, position: position, logger: logger

      if log_batch_size && (count % log_batch_size == 0)
        batch_rps   = log_batch_size / (Time.now - batch_start_time)
        overall_rps = count / (Time.now - start_time)
        logger.send(settings['log.batch_size.severity'].downcase.to_sym, "Omelette::Importer#process, read #{count} records at id:#{context.source_record_id}; #{'%.0f' % batch_rps}/s this batch, #{'%.0f' % overall_rps}/s overall")
        batch_start_time = Time.now
      end

      thread_pool.maybe_in_thread_pool(context) do |context|
        map_to_context! context
        if context.skip?
          log_skip context
        else
          writer.put context
        end
      end
    end

    $stderr.write "\n" if settings['debug_ascii_progress'].to_s == 'true'

    logger.debug 'Shutting down #processing mapper threadpool...'
    thread_pool.shutdown_and_wait
    logger.debug '#processing mapper threadpool shutdown complete.'

    thread_pool.raise_collected_exception!

    writer.close if writer.respond_to?(:close)

    @after_processing_steps.each do |step|
      begin
        step.execute
      rescue Exception => e
        logger.fatal("Unexpected exception #{e} when executing #{step}")
        raise e
      end
    end

    elapsed = Time.now - start_time
    avg_rps = (count / elapsed)
    logger.info "finished Indexer#process: #{count} records in #{'%.3f' % elapsed} seconds; #{'%.1f' % avg_rps} records/second overall."

    if writer.respond_to?(:skipped_record_count) && writer.skipped_record_count > 0
      logger.error "Indexer#process returning 'false' due to #{writer.skipped_record_count} skipped records."
      return false
    end

    return true
  end

  def reader_class
    unless defined? @reader_class
      @reader_class = Object.const_get(settings['reader_class_name']) rescue nil
    end
    return @reader_class
  end

  def writer_class
    writer.class
  end

  # Instantiate a Omelette Reader, using class set
  # in #reader_class, initialized with io_stream passed in
  def reader!(ids)
    return reader_class.new(settings.merge('logger' => logger), ids)
  end

  # Instantiate a Writer, suing class set in #writer_class
  def writer!
    writer_class = @writer_class || Object.const_get(settings['writer_class_name']) rescue nil
    writer_class.new(settings.merge('logger' => logger))
  end

  def writer
    @writer ||= settings['writer'] || writer!
  end

  # Log that the current record is being skipped, using
  # data in context.position and context.skipmessage
  def log_skip(context)
    logger.debug "Skipped record #{context.position}: #{context.skipmessage}"
  end
  private :log_skip

  def log_mapping_errors(context, import_step)
    begin
      yield
    rescue Exception => ex
      msg = "Unexpected error on record id `#{context.source_item_id}` at file position #{context.position}\n"
      msg += "    while executing #{import_step.inspect}\n"
      msg += Omelette::Util.exception_to_log_message(e)

      logger.error msg
      begin
        logger.debug "Item: #{context.source_item.to_s}"
      rescue Exception => item_exception
        logger.debug "(Could not log item, #{item_exception})"
      end
      raise ex
    end
  end
  private :log_mapping_errors

  # Create logger according to settings
  def create_logger
    logger_level  = settings['log.level'] || 'info'

    # log everything to STDERR or specified logfile
    logger        = Yell::Logger.new(:null)
    logger.format = logger_format
    logger.level  = logger_level

    logger_destination = settings['log.file'] || 'STDERR'
    # We intentionally repeat the logger_level
    # on the adapter, so it will stay there if overall level
    # is changed.
    case logger_destination
      when 'STDERR'
        logger.adapter :stderr, level: logger_level, format: logger_format
      when 'STDOUT'
        logger.adapter :stdout, level: logger_level, format: logger_format
      else
        logger.adapter :file, logger_destination, level: logger_level, format: logger_format
    end


    # ADDITIONALLY log error and higher to....
    if settings['log.error_file']
      logger.adapter :file, settings['log.error_file'], :level => 'gte.error'
    end

    return logger
  end
  private :create_logger

  def logger_format
    format = settings['log.format'] || '%d %5L %m'
    format = case format
               when 'false' then
                 false
               when '' then
                 nil
               else
                 format
             end
  end
  private :logger_format
end