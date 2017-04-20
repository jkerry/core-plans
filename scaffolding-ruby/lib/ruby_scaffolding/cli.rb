# -*- encoding: utf-8 -*-

require "ruby_scaffolding/gemfile_parser"

require "optparse"

module RubyScaffolding
  module Subcommand
    class RubyVersion
      def initialize(opts)
        @opts = opts
      end

      def run
        Dir.chdir(File.dirname(@opts[:lockfile])) do
          parser = RubyScaffolding::GemfileParser.new(
            File.basename(@opts[:lockfile]), @opts[:gemfile])
          version = parser.ruby_version
          if !version.nil?
            puts version
          else
            $stderr.puts "No Ruby version found in #{@opts[:lockfile]}"
            exit 10
          end
        end
      end
    end

    class HasGem
      def initialize(opts)
        @opts = opts
      end

      def run
        Dir.chdir(File.dirname(@opts[:lockfile])) do
          parser = RubyScaffolding::GemfileParser.new(
            File.basename(@opts[:lockfile]))
          if parser.has_gem?(@opts[:gem_name])
            puts "true"
          else
            puts "false"
            exit 10
          end
        end
      end
    end
  end

  class CLI
    def self.run
      new.run
    end

    VERSION = "@version@"
    AUTHOR = "@author@"

    SUBCOMMANDS = {
      "ruby-version" => RubyScaffolding::Subcommand::RubyVersion,
      "has-gem" => RubyScaffolding::Subcommand::HasGem,
    }

    def initialize
      name = File.basename($0)
      @options = {}
      @global_parser = OptionParser.new do |opts|
        opts.banner = <<-_USAGE_
#{name} #{VERSION}

Authors: #{AUTHOR}

USAGE:
    #{name} [SUBCOMMAND]

FLAGS:
_USAGE_
        opts.on("-h", "--help", "Prints help information") do
          puts opts
          exit
        end
        opts.on("-V", "--version", "Prints version information") do
          puts "#{name} #{VERSION}"
          exit
        end
        opts.separator <<-_USAGE_

SUBCOMMANDS:
    ruby-version      Determine version of Ruby from Gemfile
_USAGE_
      end
      subcommand_parsers = {
        "ruby-version" => OptionParser.new do |opts|
          opts.banner = <<-_USAGE_
#{name}-ruby-version

Authors: #{AUTHOR}

USAGE:
    #{name} ruby-version <LOCKFILE> [ARGS]

FLAGS:
    -h, --help       Prints help information

ARGS:
    <LOCKFILE>       The path to a Gemfile.lock (ex: ./Gemfile.lock)
    <GEMFILE>        The optional path to a Gemfile (ex: ./Gemfile)
_USAGE_
        end,
        "has-gem" => OptionParser.new do |opts|
          opts.banner = <<-_USAGE_
#{name}-has-gem

Authors: #{AUTHOR}

USAGE:
    #{name} has-gem <LOCKFILE> <GEM_NAME>

FLAGS:
    -h, --help       Prints help information

ARGS:
    <LOCKFILE>       The path to a Gemfile.lock (ex: ./Gemfile.lock)
    <GEM_NAME>       The gem name to look for (ex: rails)
_USAGE_
        end,
      }
      @global_parser.order!
      subcommand = ARGV.shift
      die("Subcommand required!") if subcommand.nil?
      subcommand_parsers.fetch(subcommand) {|key|
        die("Invalid subcommand: #{subcommand}")
      }.order!
      case subcommand
      when "ruby-version"
        @options[:lockfile] = ARGV.shift
        if @options[:lockfile].nil?
          die("Missing required: <LOCKFILE>", subcommand_parsers[subcommand])
        end
        @options[:gemfile] = ARGV.shift
      when "has-gem"
        @options[:lockfile] = ARGV.shift
        if @options[:lockfile].nil?
          die("Missing required: <LOCKFILE>", subcommand_parsers[subcommand])
        end
        @options[:gem_name] = ARGV.shift
        if @options[:gem_name].nil?
          die("Missing required: <GEM_NAME>", subcommand_parsers[subcommand])
        end
      end
      @subcommand_klass = SUBCOMMANDS.fetch(subcommand)
    end

    def run
      @subcommand_klass.new(@options).run
    end

    private

    attr_reader :options, :global_parser

    def die(msg, parser = global_parser)
      $stderr.puts msg
      $stderr.puts
      $stderr.puts parser
      exit 1
    end
  end
end
