require 'shiba/explain/check_support'

module Shiba
  class Explain
    class Checks
      include CheckSupport
      extend CheckSupport::ClassMethods

      def initialize(rows, index, stats, options, result)
        @rows = rows
        @row = rows[index]
        @index = index
        @stats = stats
        @options = options
        @result = result
        @tbl_message = {}
      end

      attr_reader :cost

      def table
        @row['table']
      end

      def table_size
        @stats.table_count(table)
      end

      def add_message(tag, extra = {})
        @result.messages << { tag: tag, size: table_size, table: table }.merge(extra)
      end

      check :check_derived
      def check_derived
        if table =~ /<derived.*?>/
          # select count(*) from ( select 1 from foo where blah )
          add_message('derived_table', size: nil)
          @cost = 0
        end
      end

      check :tag_query_type
      def tag_query_type
        @access_type = @row['access_type']

        if @access_type.nil?
          @cost = 0
          return
        end

        @access_type = 'tablescan' if @access_type == 'ALL'
        @access_type = "access_type_" + @access_type
      end

      check :check_join
      def check_join
        if @row['join_ref']
          @access_type.sub!("access_type", "join_type")
          # TODO MAYBE: are multiple-table joins possible?  or does it just ref one table?
          ref = @row['join_ref'].find { |r| r != 'const' }
          table = ref.split('.')[1]
          @tbl_message['join_to'] = table
        end
      end

      #check :check_index_walk
      # disabling this one for now, it's not quite good enough and has a high
      # false-negative rate.
      def check_index_walk
        if first['index_walk']
          @cost = limit
          add_message("index_walk")
        end
      end

      check :check_key_size
      def check_key_size
        # TODO: if possible_keys but mysql chooses NULL, this could be a test-data issue,
        # pick the best key from the list of possibilities.
        #
        if @row['key']
          rows_read = @stats.estimate_key(table, @row['key'], @row['used_key_parts'])
        else
          rows_read = table_size
=begin
          TBD: this used to work in the one-row world, how do we adapt this to the new stuff?
          this is all about the optimizer outsmarting us.  So we
          may force the plan, or we may try to fool the optimizer.  dunno.

          if @row['possible_keys'].nil?
            # if no possibile we're table scanning, use PRIMARY to indicate that cost.
            # note that this can be wildly inaccurate bcs of WHERE + LIMIT stuff.
          else
            if @options[:force_key]
              # we were asked to force a key, but mysql still told us to fuck ourselves.
              # (no index used)
              #
              # there seems to be cases where mysql lists `possible_key` values
              # that it then cannot use, seen this in OR queries.
              @cost = table_size
            else
              possibilities = [table_size]
              possibilities += @row['possible_keys'].map do |key|
                estimate_row_count_with_key(key)
              end
              @cost = possibilities.compact.min
            end
          end
=end
        end

        # TBD: this appears to come from a couple of bugs.
        # one is we're not handling mysql index-merges, the other is that
        # we're not handling mysql table aliasing.
        if rows_read.nil?
          rows_read = 1
        end

        if @row['join_ref']
          # when joining, we'll say we read "@cost" rows -- but up to
          # a max of the table size.  I'm not sure this assumption is *exactly*
          # true but it feels good enough to start; a decent hash join should
          # nullify the cost of re-reading rows.  I think.
          @cost = [@result.result_size * rows_read, table_size || 2**32].min

          # poke holes in this.  Is this even remotely accurate?
          # We're saying that if we join to a a table with 100 rows per item
          # in the index, for each row we'll be joining in 100 more rows.  Is that true?
          @result.result_size *= rows_read
        else
          @cost = rows_read
          @result.result_size += rows_read
        end

        @result.cost += @cost

        @tbl_message['cost'] = @cost
        @tbl_message['index'] = @row['key']
        @tbl_message['index_used'] = @row['used_key_parts']
        add_message(@access_type, @tbl_message)
      end

      def estimate_row_count_with_key(key)
        explain = Explain.new(@sql, @stats, @backtrace, force_key: key)
        explain.run_checks!
      rescue Mysql2::Error => e
        if /Key .+? doesn't exist in table/ =~ e.message
          return nil
        end

        raise e
      end

      def run_checks!
        _run_checks! do
          :stop if @cost
        end
      end
    end
  end
end
