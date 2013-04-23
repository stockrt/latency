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

  # Splash.
  puts "
  URL:          #{url}
  Host:         #{uri.host}
  Port:         #{uri.port}
  Channel:      #{opts[:channel]}
  Pubdelay:     #{opts[:pubdelay]} seconds
  Outfile:      #{opts[:outfile]}
  Pub URI:      #{opts[:pub]}
  Sub URI:      #{opts[:sub]}
  Max latency:  #{opts[:max]} seconds
  Verbosity:    #{opts[:verbose]}
".light_cyan
  sleep 3

  # Pub.
  Process.fork { publisher(opts, uri) }

  # Sub.
  Process.fork { subscriber(opts, uri) }

  Process.waitall
end

# Pub.
def publisher(opts, uri)
  pub_uri = "#{opts[:pub]}?id=#{opts[:channel]}"
  buffer = ''
  Net::HTTP.start(uri.host, uri.port) do |http|
    loop do
      send_timestamp = Time.now.strftime('%s.%L')
      message = "TS:#{send_timestamp}:"
      puts "[Publisher] Sending: #{message}".light_yellow if opts[:verbose] > 0
      puts "[Publisher] URL: #{uri.scheme}://#{uri.host}:#{uri.port}#{pub_uri}".light_yellow if opts[:verbose] > 2
      http.request_post(URI.escape(pub_uri), message) do |response|
        puts "[Publisher] Feedback: #{response.read_body}".light_yellow if opts[:verbose] > 1
      end
      unless opts[:pubdelay] == 0
        puts "[Publisher] Sleeping #{opts[:pubdelay]} seconds".light_yellow if opts[:verbose] > 2
        sleep opts[:pubdelay]
      end
    end
  end
end

# Sub.
def subscriber(opts, uri)
  sub_uri = "#{opts[:sub]}/#{opts[:channel]}"
  buffer = ''
  Net::HTTP.start(uri.host, uri.port) do |http|
    puts "[Subscriber] URL: #{uri.scheme}://#{uri.host}:#{uri.port}#{sub_uri}".light_cyan if opts[:verbose] > 2
    http.request_get(URI.escape(sub_uri)) do |response|
      response.read_body do |stream|
        recv_timestamp = Time.now.to_f
        buffer += stream
        # Compose line.
        while message = buffer.slice!(/.+\r\n/)
          puts "[Subscriber] Received: #{message}".light_cyan if opts[:verbose] > 0
          # Parse sent timestamp.
          match_data = /TS:(?<ts>\d+\.\d+):/.match(message)
          send_timestamp = match_data ? match_data[:ts].to_f : nil
          puts "[Subscriber] Extracted timestamp: #{send_timestamp}".light_cyan if opts[:verbose] > 3
          puts "[Subscriber] Timestamp now: #{recv_timestamp}".light_cyan if opts[:verbose] > 3
          unless send_timestamp.nil?
            latency = recv_timestamp - send_timestamp
            # Max latency.
            if latency > opts[:max]
              puts "Latency: #{latency}".light_red
            else
              puts "Latency: #{latency}".light_green
            end
            # Write outfile.
            if opts.outfile?
              puts "[Subscriber] Writing last timestamp to outfile: #{opts[:outfile]}".light_cyan if opts[:verbose] > 2
              File.open(opts[:outfile], 'wt').write("#{latency}\n")
            end
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
    on :c=, :channel=, 'Channel.', :default => 'latency'
    on :d=, :pubdelay=, 'Publisher delay (in seconds) between messages.', :as => Float, :default => 1
    on :o=, :outfile=, 'Output file (write the last latency timming to use in any external tool).'
    on :p=, :pub=, 'Pub URI.', :default => '/pub'
    on :s=, :sub=, 'Sub URI.', :default => '/sub'
    on :m=, :max=, 'Max latency before alert.', :as => Float, :default => 0.5
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
  Process.waitall
  exit 0
end
