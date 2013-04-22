#!/usr/bin/env ruby
# coding: utf-8

##############
## REQUIRES ##
##############

require 'net/http'

##########
## MAIN ##
##########

def main
  # Usage.
  abort "Usage: #{$0} <domain> <port> <mode>" if ARGV.size != 3

  # Params.
  domain = ARGV[0]
  port = ARGV[1].to_i
  mode = ARGV[2]

  case mode
  when 'pub'
    publisher(domain, port)
  when 'sub'
    subscriber(domain, port)
  else
    abort "Invalid mode: \"#{mode}\". Valid modes are: \"pub\" or \"sub\""
  end
end

def publisher(domain, port)
  buffer = ''
  Net::HTTP.start(domain, port) do |http|
    loop do
      send_timestamp = Time.now.strftime('%s.%L')
      message = "TS:#{send_timestamp}:"
      http.request_post(URI.escape('/pub?id=latency'), message) do |response|
        puts response.read_body
      end
    end
  end
end

def subscriber(domain, port)
  buffer = ''
  Net::HTTP.start(domain, port) do |http|
    http.request_get(URI.escape('/sub/latency')) do |response|
      response.read_body do |stream|
        recv_timestamp = Time.now.to_f
        buffer += stream
        while line = buffer.slice!(/.+\r\n/)
          match_data = /TS:(?<ts>\d+\.\d+):/.match(line)
          send_timestamp = match_data ? match_data[:ts].to_f : nil
          unless send_timestamp.nil?
            latency = recv_timestamp - send_timestamp
            puts "Latency: #{latency}s"
          end
        end
      end
    end
  end
end

begin
  main
rescue Interrupt
  puts
  puts 'Exiting.'
  exit 0
end
