#!/usr/bin/env ruby

require 'date'
require 'time'

class Time
  require 'tzinfo'
  def to_datetime_in_timezone tzstring
    tz = TZInfo::Timezone.get tzstring
    p = tz.period_for_utc self
    e = self + p.utc_offset
    e.to_datetime.strftime("%d/%b/%Y:%H:%M:%S %Z")
  end
end

class LogConverter
  DEFAULT_TIMEZONE = 'America/Los_Angeles'.freeze

  def self.to_weblog(input_log_glob, output_log=nil)
    new(input_log_glob, output_log).to_weblog
  end

  def initialize(input_log_glob, output_log=nil)
    @log_glob = input_log_glob
    fail("Missing log(s): #{Dir.glob(@log_glob).inspect}") if Dir.glob(@log_glob) == []
    @output_log = output_log
    fail("Output log already exists: #{@output_log.inspect}") if File.exists?(@output_log)
    warn "Output File: #{@output_log.inspect}"
  end

  def to_weblog
    File.open(@output_log, "w") do |output_log|
      weblog_data do |weblog_line|
        # log-format %h %^[%d:%t %^] "%r" %s %b "%R" "%u" %L
        # 172.31.32.196 - - [26/Jan/2017:03:10:03 +0000] "GET /path/path?_=148545390 HTTP/1.1" 200 2511 "https://www.somesite.com/referrer" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.12; rv:50.0) Gecko/20100101 Firefox/50.0" "-"
        t = Time.parse(weblog_line["RequestStartTime"])
        log_time = t.to_datetime_in_timezone(DEFAULT_TIMEZONE)
        output_log.puts %Q|#{weblog_line["Host"]} - - [#{log_time}] "#{weblog_line["RequestMethod"]} #{weblog_line["RequestPath"]} HTTP/1.1" #{weblog_line["CompletionCode"]} - "#{weblog_line["Referrer"] || '-'}" "#{weblog_line["UserAgent"]}" #{weblog_line["CompletionMS"]}|
      end
    end
  end


  private

  def weblog_data(&block)
    trx_id = "NON-EXISTENT"
    got_user_agent = false
    completed = false
    started = false
    weblog_line = {}

    logs = Dir.glob(@log_glob)
    logs.each do |log|
      File.open(log, "r").each_line do |line|
        if started && got_user_agent && completed
          block.call(weblog_line.dup)
          got_user_agent = false
          completed = false
          started = false
          weblog_line = {}
        end

        retry_times = 3
        begin
          case line
          when /\s+Referrer or Referer\:/
            # I, [2017-01-23T22:00:22.932997 #5488]  INFO -- : [f40bf4ee-6a32-489f-a13a-74a2a6caa43d] [922.51.62.197]
            # [SEO]   Referrer or Referer: https://www.referrersite.com/path/some-resource-id
            if matches = line.match(/\[SEO\]\s+Referrer or Referer:\s+(.+)$/)
              if line =~ %r|#{trx_id}|
                referrer_url = matches[1]
                weblog_line["Referrer"] = referrer_url
              end
            end
          when /\s+User Agent\:/
            # I, [2017-01-23T06:49:05.603598 #31865]  INFO -- : [f3cfd066-301f-48b4-84dd-be5aae457063] [982.41.82.16]
            # [SEO]   User Agent: Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P)
            # AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2272.96 Mobile Safari/537.36
            # (compatible; Googlebot/2.1; +http://www.google.com/bot.html)
            if matches = line.match(/\[SEO\]\s+User Agent:\s+(.+)$/)
              if line =~ %r|#{trx_id}|
                user_agent = matches[1]
                weblog_line["UserAgent"] = user_agent
                got_user_agent = true
              end
            else
              warn("line doesn't match expected /User Agent/ regexp: #{line.inspect}")
            end
          when /\]\s+Completed\s+/
            #I, [2017-01-23T16:50:52.007180 #2805]  INFO -- : [gf306912-04b4-4tba-a243-cd61af6f941e]
            #[982.51.66.88] Completed 200 OK in 273ms (Views: 166.6ms | ActiveRecord: 99.5ms)
            if matches = line.match(/\w,\s+\[([^\s]+)\s+\#\d+\]\s+.*Completed\s+(\d+)\s+([\w\s]+)\s+in\s+(\d+)ms\s+\(([^\)]+)\)/)
              if line =~ %r|#{trx_id}|
                request_end_time = matches[1]
                code = matches[2]
                status = matches[3]
                total_ms = matches[4]
                time_details = matches[5]
                weblog_line["RequestEndTime"] = request_end_time
                weblog_line["CompletionCode"] = code
                weblog_line["CompletionStatus"] = status
                weblog_line["CompletionMS"] = total_ms
                weblog_line["CompletionTimeDetail"] = time_details
                completed = true
              end
            else
              warn("line doesn't match expected /Completed/ regexp: #{line.inspect}")
            end
          when /\]\s+Started\s+/
            # I, [2017-01-23T01:14:47.043040 #27677]  INFO -- : [05c649bd-461d-4048-8e71-0777db5e05bb] [1.1.1.1]
            # Started GET "/path/item-id" for 1.1.1.1 at 2017-01-23 01:14:47 +0000
            #                                           for 1:1:1:b5:e0:65:95 at 2017-01-26 00:19:51 +0000
            #support w/ ipv6 addresses too!
            if matches = line.match(/\w,\s+\[([^\s]+)\s+\#\d+\]\s+(\w+)\s+[^\[]+\[([^\]]+)\].+\s+Started\s+(\S+)\s*.\"(.+)"\s+for\s+([\.\w\:]+)\s+at\s+(.+\+0000)/)
              _request_start_time = matches[1]
              request_status = matches[2]
              trx_id = matches[3]

              http_request_method = matches[4]
              request_path = matches[5]
              ip = matches[6]
              datetime = matches[7]

              weblog_line["RequestStartTime"] = datetime #_request_start_time
              weblog_line["RequestStatus"] = request_status
              weblog_line["TRX_ID"] = trx_id

              weblog_line["Host"] = ip #_host
              weblog_line["RequestMethod"] = http_request_method
              weblog_line["RequestPath"] = request_path
              started = true
            else
              warn("line doesn't match expected /Started/ regexp: #{line.inspect}")
            end
          end
          retry_times = 3
        rescue ArgumentError
          retry_times -= 1
          if retry_times > 0
            if ! line.valid_encoding?
              line = line.encode("UTF-16be", invalid: :replace, replace: "?").encode('UTF-8')
            end
            warn "retrying line: #{line.inspect}"
            retry
          else
            warn "trouble with line: #{line.inspect}"
            next
          end
        end
      end
    end
  end

end

if __FILE__ == $PROGRAM_NAME
  input_log_glob = ARGV[0]
  output_log = ARGV[1]
  format = ARGV[2] || 'weblog'
  if 'weblog' == format
    warn "LogConverter.to_weblog(#{input_log_glob.inspect}, #{output_log})..."
    LogConverter.to_weblog(input_log_glob, output_log)
  end
  warn "done."
end
