require 'thor'

module Omelette
  class CommandLine < Thor
    desc 'import', 'import a file'
    method_option :config, aliases: '-c', desc: 'Configuration file', required: true
    method_option :settings, aliases: '-s', desc: 'Setting', required: false, type: :hash
    method_option :debug, aliases: '-d', desc: 'Turn on debug logging', required: false, type: :boolean, default: false
    method_option :writer, aliases: '-w', desc: 'Writer Class name', required: false, default: 'Omelette::OmekaJsonWriter', type: :string
    method_option :reader, aliases: '-r', desc: 'Reader Class name', required: false, default: 'Omelette::XmlReader', type: :string
    def import(files)
      settings = assemble_settings_hash(options)
      importer = Omelette::Importer.new settings
      importer.process files
    end
    no_commands {
      def assemble_settings_hash(options)
        settings = options['settings']
        if options['debug'] == true
          settings['log.level'] = 'debug'
        end

        if options['writer']
          settings['writer_class_name'] = options['writer']
        end
        if options['reader']
          settings['reader_class_name'] = options['reader']
        end

        return settings
      end
    }
  end
end