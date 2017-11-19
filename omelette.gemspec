
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "omelette/version"

Gem::Specification.new do |spec|
  spec.name          = "omelette"
  spec.version       = Omelette::VERSION
  spec.authors       = ["Dazhi Jiao"]
  spec.email         = ["dazhi.jiao@gmail.com"]

  spec.summary       = "A tool that imports data into Omeka using the Omeka API"
  spec.description   = "Omelette is a Ruby gem that uses the Omeka API to import data. " \
                       "It has a DSL and can be used or extended to process almost any kinds of data." \
                       "It was inspired by the traject gem."
  spec.homepage      = "http://github.com/jiaola/omelette"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "thor", "~> 0.20"
  spec.add_runtime_dependency "nokogiri", "~> 1.8"
  spec.add_runtime_dependency "rest-client", "~> 2.0"
  spec.add_runtime_dependency "concurrent-ruby", "~> 1.0"
  spec.add_runtime_dependency "hashie", "~> 3.5"
  spec.add_runtime_dependency "yell", "~> 2.0"
  spec.add_runtime_dependency "mysql2", "~> 0.4"
  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
