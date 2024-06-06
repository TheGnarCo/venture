lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'venture/about'

Gem::Specification.new do |gem|
  gem.name  = "venture"
  gem.version = Venture::VERSION
  gem.summary = Venture::SUMMARY
  gem.description = Venture::SUMMARY
  gem.authors = ["Erik Cameron", "Steve Zelaznik"]
  gem.license = "MIT"

  gem.add_dependency "activerecord", ">= 5"
  gem.add_dependency "request_store", "~> 1.5.0"

  gem.add_development_dependency "rspec-rails"
end
