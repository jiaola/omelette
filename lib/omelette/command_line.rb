require 'thor'

module Omelette
  class CommandLine < Thor
    desc 'import', 'import a file'
    def import(ids = nil)
      puts 'omelette import: To be implemented'
    end
  end
end