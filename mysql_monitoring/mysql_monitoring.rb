require 'rubygems'
require 'set'
class MysqlMonitoring< Scout::Plugin
  ENTRIES = %w(Com_insert Com_select Com_update Com_delete Com_replace).to_set
  def build_report
    # need the mysql gem
    begin
      require 'mysql'
    rescue LoadError => e
      return errors << {:subject => "Unable to gather Mysql query statistics",
                          :body => "Unable to find the mysql gem. Please install the gem (sudo gem install mysql)" }
    end
    
    user = @options['user'] || 'root'
    password, host, port, socket = @options.values_at( *%w(password host port socket) )

    now = Time.now
    mysql = Mysql.connect(host, user, password, nil, port.to_i, socket)
    result = mysql.query('SHOW /*!50002 GLOBAL */ STATUS')

    rows = []
    total = 0
    result.each do |row| 
      rows << row if ENTRIES.include?(row.first)

      total += row.last.to_i if row.first[0..3] == 'Com_'
    end
    result.free

    report = {}
    rows.each do |row|
      name = row.first[/_(.*)$/, 1]
      report[name] = calculate_counter(now, name, row.last.to_i)
    end
    report['total'] = calculate_counter(now, 'total', total)

    { :report => report, :memory => @memory }
  end

  private
  def calculate_counter(current_time, name, value)
    result = nil

    if @memory[name] && @memory[name].is_a?(Hash)
      last_time, last_value = @memory[name].values_at(:time, :value)

      # We won't log it if the value has wrapped
      if value >= last_value
        elapsed_seconds = last_time - current_time
        elapsed_seconds = 1 if elapsed_seconds < 1

        result = value - last_value

        if @options['calculate_per_second']
          result = result / elapsed_seconds.to_f
        end
      end
    end

    @memory[name] = { :time => current_time, :value => value }

    result
  end
end