# -*- encoding: utf-8 -*-

require "bundler"
require "bundler/definition"
require "bundler/lockfile_parser"
require "pathname"

module RubyScaffolding
  class GemfileParser
    def initialize(lockfile_path, gemfile_path = nil)
      @lockfile_path = Pathname(lockfile_path)
      @gemfile_path = Pathname(gemfile_path) unless gemfile_path.nil?
      if !@lockfile_path.file?
        raise "Lockfile not found: #{@lockfile_path}"
      end
      if @gemfile_path && !@gemfile_path.file?
        raise "Gemfile not found: #{@gemfile_path}"
      end
    end

    def ruby_version
      lockfile_ruby_version || gemfile_ruby_version
    end

    def has_gem?(name)
      specs.key?(name)
    end

    private

    def gemfile_ruby_version
      return nil if @gemfile_path.nil?

      version = gemfile_definition.ruby_version
      version && version.single_version_string
    end

    def lockfile_ruby_version
      version = locked_gems.ruby_version
      version && version.sub(/p\d+/, "")
    end

    def gemfile_definition
      @gemfile_definition ||= Bundler::Definition.build(@gemfile_path, nil, nil)
    end

    def locked_gems
      @locked_gems ||= begin
        contents = Bundler.read_file(@lockfile_path)
        Bundler::LockfileParser.new(contents)
      end
    end

    def specs
      @specs ||= locked_gems.specs.
        each_with_object({}) { |spec, hash| hash[spec.name] = spec }
    end
  end
end
