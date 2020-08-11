require 'shiba/query'
require 'shiba/backtrace'

module Shiba
  # Logs ActiveRecord SELECT queries that originate from application code.
  class QueryWatcher

    attr_reader :queries

    def initialize(file)
      @file = file
      # fixme mem growth on this is kinda nasty
      @queries = {}
    end

    def call(name, start, finish, id, payload)
      sql = payload[:sql]
      return if !sql.start_with?("SELECT")

      if postgres? && sql.include?("$1")
        type_casted_binds = payload[:type_casted_binds]
        sql = interpolate(sql, type_casted_binds)
      end

      sql = sql.gsub(/\n/, ' ')

      fingerprint = Query.get_fingerprint(sql)
      return if @queries[fingerprint]

      lines = Backtrace.from_app
      return if !lines

      @file.puts("#{sql} /*shiba#{lines}*/")
      @queries[fingerprint] = true
    end

    def interpolate(sql, binds)
      binds.each_with_index do |val, i|
        sql = sql.sub("$#{i +1}", ActiveRecord::Base.connection.quote(val))
      end
      sql
    end

    def postgres?
      Shiba::ActiveRecordIntegration.connection_options.fetch('server', nil) != 'mysql'
    end
  end
end
