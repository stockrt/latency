#!/usr/bin/env ruby
# coding: utf-8

##############
## REQUIRES ##
##############

require 'colorize'
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
      timestamp = Time.now.strftime('%s.%L')
      message = "TS:#{timestamp}:"
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
        buffer += stream
        while line = buffer.slice!(/.+\r\n/)
          timestamp = line.start_with?('TS:') ? line.split(':')[1].to_i : nil
          unless timestamp.nil?
            latency = Time.now - Time.at(timestamp)
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
