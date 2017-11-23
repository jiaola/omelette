require 'yell'
require 'omelette/importer/context'
require 'omelette/importer/settings'
require 'omelette/importer/errors'
require 'omelette/importer/steps'
require 'omelette/thread_pool'
require 'omelette/macros/xpath'
require 'mysql2'

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

  def name_id_maps
    if @name_id_maps.nil?
      @name_id_maps = {}
      @name_id_maps[:elements] = Omelette::Util.build_elements_map @settings['omeka_api_root']
      @name_id_maps[:item_types] = Omelette::Util.build_item_types_map @settings['omeka_api_root']
      # TODO: Make this a generic db client, instead of just for MySQL
      db_client = create_db_client
      @name_id_maps[:collections] = Omelette::Util.build_collections_map db_client
      @name_id_maps[:items] = Omelette::Util.build_items_map db_client
      db_client.close if db_client
    end
    return @name_id_maps
  end

  def create_db_client
    Mysql2::Client.new(
        host: @settings['omeka_db_host'],
        username: @settings['omeka_db_username'],
        password: @settings['omeka_db_password'],
        database: @settings['omeka_db_name'],
        port: @settings['omeka_db_port']
    )
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

  def to_item_type(item_type_name, opts={}, &block)
    source_locaiton = Omelette::Util.extract_caller_location(caller.first)
    @import_steps << ToItemTypeStep.new(item_type_name, opts, source_locaiton, &block)
  end

  # def to_element(element_name, element_set_name, aLambda = nil, &block)
  #   @import_steps << ToElementStep.new(element_name, element_set_name, elements_map, aLambda, block, Omelette::Util.extract_caller_location(caller.first))
  # end

  # Processes a single item according to extracting rules set up in
  # this importer. Returns the output hash (a hash whose keys are
  # string fields, and values are arrays of one or more values in that field)
  #
  # This is a convenience shortcut for #map_to_context -- use that one
  # if you want to provide addtional context
  # like position, and/or get back the full context.
  def map_item(item)
    context = Context.new(source_item: item, settings: settings, mappings: name_id_maps)
    map_to_context context
    return context.omeka_item
  end

  def map_to_context(context)
    @import_steps.each do |import_step|
      break if context.skip?
      next unless import_step.can_process? context.source_item_id
      # set the to_element step for error reporting
      context.import_step = import_step
      item = Omelette::Util.log_mapping_errors context, import_step do
        import_step.execute context
      end
      # merge the new item to the one in context. Concat the element_texts values, and overwrite
      # any other existing keys
      context.omeka_item.merge!(item) { |_k, c, i|
        if c.is_a?(Array) and i.is_a?(Array)
          c | i
        elsif c.is_a?(Array)
          c << i
        elsif i.is_a?(Array)
          i << c
        else
          i
        end
      }
      # Set Omeka Item ID
      context.omeka_item_id = name_id_maps[:items][item[:identifier]]
      # Unset the import step after it's finished
      context.import_step = nil
    end
    return context
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

      context = Context.new source_item: item, source_item_id: item_id, settings: settings, position: position, logger: logger, mappings: name_id_maps

      if log_batch_size && (count % log_batch_size == 0)
        batch_rps   = log_batch_size / (Time.now - batch_start_time)
        overall_rps = count / (Time.now - start_time)
        logger.send(settings['log.batch_size.severity'].downcase.to_sym, "Omelette::Importer#process, read #{count} records at id:#{context.source_record_id}; #{'%.0f' % batch_rps}/s this batch, #{'%.0f' % overall_rps}/s overall")
        batch_start_time = Time.now
      end

      # check the item_type
      # use the correct item_type
      thread_pool.maybe_in_thread_pool(context) do |context|
        map_to_context context
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