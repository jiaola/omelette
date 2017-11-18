class Omelette::Importer
  # Arity error on a passed block
  class ArityError < ArgumentError;
  end
  class NamingError < ArgumentError;
  end

  # Raised by #load_config_file when config file can not
  # be processed.
  #
  # The exception #message includes an error message formatted
  # for good display to the developer, in the console.
  #
  # Original exception raised when processing config file
  # can be found in #original. Original exception should ordinarily
  # have a good stack trace, including the file path of the config
  # file in question.
  #
  # Original config path in #config_file, and line number in config
  # file that triggered the exception in #config_file_lineno (may be nil)
  #
  # A filtered backtrace just DOWN from config file (not including trace
  # from omelette loading config file itself) can be found in
  # #config_file_backtrace
  class ConfigLoadError < StandardError
    # We'd have #cause in ruby 2.1, filled out for us, but we want
    # to work before then, so we use our own 'original'
    attr_reader :original, :config_file, :config_file_lineno, :config_file_backtrace

    def initialize(config_file_path, original_exception)
      @original              = original_exception
      @config_file           = config_file_path
      @config_file_lineno    = Omelette::Util.backtrace_lineno_for_config(config_file_path, original_exception)
      @config_file_backtrace = Omelette::Util.backtrace_from_config(config_file_path, original_exception)
      message                = "Error loading configuration file #{self.config_file}:#{self.config_file_lineno} #{original_exception.class}:#{original_exception.message}"

      super(message)
    end
  end
end