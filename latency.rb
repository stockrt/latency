#!/usr/bin/env ruby
# coding: utf-8

# === Author
#
# Rogério Carvalho Schneider <stockrt@gmail.com>

##############
## REQUIRES ##
##############

require 'slop'
require 'colorize'
require 'net/http'
require 'uri'

##########
## MAIN ##
##########

def main(opts)
  # URL.
  url = ARGV[0]

  # Wrong number of command line arguments.
  if url.nil? and not opts.help?
    puts opts
    exit 1
  end

  # It is not an error to ask for help.
  exit 0 if opts.help?

  # Parse.
  uri = URI(url)

  # Pub.
  Process.fork do
    publisher(opts, uri.host, uri.port)
  end

  # Sub.
  Process.fork do
    subscriber(opts, uri.host, uri.port)
  end

  Process.wait
end

# Pub.
def publisher(opts, domain, port)
  buffer = ''
  Net::HTTP.start(domain, port) do |http|
    loop do
      send_timestamp = Time.now.strftime('%s.%L')
      message = "TS:#{send_timestamp}:"
      http.request_post(URI.escape("#{opts[:pub]}?id=#{opts[:channel]}"), message) do |response|
        puts response.read_body if opts[:verbose] > 0
      end
      sleep opts[:pubdelay] unless opts[:pubdelay] == 0
    end
  end
end

# Sub.
def subscriber(opts, domain, port)
  buffer = ''
  Net::HTTP.start(domain, port) do |http|
    http.request_get(URI.escape("#{opts[:sub]}/#{opts[:channel]}")) do |response|
      response.read_body do |stream|
        recv_timestamp = Time.now.to_f
        buffer += stream
        # Compose line.
        while line = buffer.slice!(/.+\r\n/)
          puts line if opts[:verbose] > 1
          # Parse sent timestamp.
          match_data = /TS:(?<ts>\d+\.\d+):/.match(line)
          send_timestamp = match_data ? match_data[:ts].to_f : nil
          unless send_timestamp.nil?
            latency = recv_timestamp - send_timestamp
            # Max latency.
            if latency > opts[:max]
              puts "Latency: #{latency}".light_red
            else
              puts "Latency: #{latency}".light_green
            end
            # Write outfile.
            File.open(opts[:outfile], 'wt').write("#{latency}\n") if opts[:outfile]
          end
        end
      end
    end
  end
end

# Command line options.
begin
  opts = Slop.parse(:help => true, :strict => true) do
    banner <<-EOS
Usage:

  latency.rb url [options]

Examples:

  latency.rb http://www.nginxpushstream.org --channel latency --pubdelay 1 --outfile output.txt
  latency.rb http://www.nginxpushstream.org -p /pub -s /sub --pubdelay 0.3
  latency.rb http://www.nginxpushstream.org --max 0.5

Options:
EOS
    on :c, :channel, 'Channel.', :default => 'latency'
    on :d, :pubdelay, 'Publisher delay (in seconds) between messages.', :as => Float, :default => 1
    on :o, :outfile, 'Output file (write the last latency timming to use in any external tool).'
    on :p, :pub, 'Pub URI.', :default => '/pub'
    on :s, :sub, 'Sub URI.', :default => '/sub'
    on :m, :max, 'Max latency before alert.', :as => Float, :default => 0.5
    on :v, :verbose, 'Verbose mode.', :as => :count
  end
rescue
  puts 'ERR: Invalid option. Try -h or --help for help.'.light_magenta
  exit 1
end

begin
  main(opts)
rescue Interrupt
  puts
  puts 'Exiting.'
  exit 0
end
