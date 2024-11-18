module Flipper
  VERSION = '1.3.1'.freeze

  REQUIRED_RUBY_VERSION = '3.1'.freeze
  NEXT_REQUIRED_RUBY_VERSION = '3.2'.freeze

  REQUIRED_RAILS_VERSION = '7.0'.freeze
  NEXT_REQUIRED_RAILS_VERSION = '7.1'.freeze

  def self.deprecated_ruby_version?
    Gem::Version.new(RUBY_VERSION) < Gem::Version.new(NEXT_REQUIRED_RUBY_VERSION)
  end
end
