#!/usr/bin/env ruby

require 'bundler/setup'
require 'shiba'
require 'shiba/cli'
require 'shiba/index'
require 'optionparser'

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: analyze.rb -h HOST -d DB -u USER -p PASS [-f QUERY_FILE] [-s STATS_FILE] "

  opts.on("-h","--host HOST", "sql host") do |h|
    options["host"] = h
  end

  opts.on("-d","--database DATABASE", "sql database") do |d|
    options["database"] = d
  end

  opts.on("-u","--user USER", "sql user") do |u|
    options["username"] = u
  end

  opts.on("-p","--password PASSWORD", "sql password") do |p|
    options["password"] = p
  end

  opts.on("-i","--index INDEX", "index of query to inspect") do |i|
    options["index"] = i.to_i
  end

  opts.on("-s","--stats FILES", "location of index statistics tsv file") do |f|
    options["stats_file"] = f
  end

  opts.on("-f", "--file FILE", "location of file containing queries") do |f|
    options["file"] = f
  end

  opts.on("--debug") do
    options["debug"] = true
  end
end

parser.parse!

["host", "database", "username", "password"].each do |opt|
  if !options[opt]
    $stderr.puts "Required: #{opt}"
    $stderr.puts parser.banner
    exit
  end
end

file = options.delete("file")
file = File.open(file, "r") if file


Shiba.configure(options)

schema_stats_fname = options["stats_file"]

if schema_stats_fname && !File.exist?(schema_stats_fname)
  $stderr.puts "No such file: #{schema_stats_fname}"
  exit 1
end

if schema_stats_fname
  schema_stats = Shiba::Index.parse(schema_stats_fname)

  local_db_stats = Shiba::Index.query(Shiba.connection)
  Shiba::Index.fuzz!(local_db_stats)
  local_db_stats.each do |table, values|
    schema_stats[table] = values unless schema_stats[table]
  end
else
  schema_stats = Shiba::Index.query(Shiba.connection)

  if Shiba::Index.insufficient_stats?(schema_stats)
    $stderr.puts "WARN: insufficient stats available in #{options["database"]}, guessing at numbers."
    $stderr.puts "To get better data please specify an index statistics file."
    sleep 0.5
    Shiba::Index.fuzz!(schema_stats)
  end
end

Shiba::Cli.analyze(file, schema_stats, options)
