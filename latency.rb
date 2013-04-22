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
  abort "#{$0} <domain> <port>" if ARGV.size != 2

  # Params.
  domain = ARGV[0]
  port = ARGV[1].to_i

  # Subscriber loop.
  Net::HTTP.start(domain, port) do |http|
    http.request_get(URI.escape('/sub/latency')) do |response|
      response.read_body do |stream|
        timestamp = stream.start_with?('TS:') ? stream.split(':')[1].to_i : nil
        unless timestamp.nil?
          latency = Time.now - Time.at(timestamp)
          puts "Latency: #{latency}s"
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
