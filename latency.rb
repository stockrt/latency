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
  abort "#{$0} <channels>" if ARGV.size != 1

  # Params.
  channels = ARGV[0].to_i

  # Loop.
  Net::HTTP.start('localhost', port=9080) do |http|
    http.request_get(URI.escape('/sub/channel')) do |response|
      response.read_body do |stream|
        puts stream
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
