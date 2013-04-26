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
  pubdelay_plural = opts[:pubdelay] == 1 ? '' : 's'
  maxlatency_plural = opts[:max] == 1 ? '' : 's'
  puts "
  URL:          #{url}
  Host:         #{uri.host}
  Port:         #{uri.port}
  Channel:      #{opts[:channel]}
  Pubdelay:     #{opts[:pubdelay]} second#{pubdelay_plural}
  Outfile:      #{opts[:outfile]}
  Pub URI:      #{opts[:pub]}
  Sub URI:      #{opts[:sub]}
  Max latency:  #{opts[:max]} second#{maxlatency_plural}
  Verbosity:    #{opts[:verbose]}
".light_cyan

  sleep 1

  # Pub.
  Process.fork do
    begin
      publisher(opts, uri)
    rescue Interrupt
      puts
      puts '[Publisher] Exiting.'.light_yellow
      exit 0
    end
  end

  sleep 0.1

  # Sub.
  Process.fork do
    begin
      subscriber(opts, uri)
    rescue Interrupt
      sleep 0.1
      puts '[Subscriber] Exiting.'.light_cyan
      exit 0
    end
  end

  Process.waitall
end

# Pub.
def publisher(opts, uri)
  pub_uri = "#{opts[:pub]}?id=#{opts[:channel]}"
  pubdelay_plural = opts[:pubdelay] == 1 ? '' : 's'
  flag_first_conn = true

  # First request.
  puts '[Publisher] Connecting...'.light_yellow if opts[:verbose] > 0
  Net::HTTP.start(uri.host, uri.port) do |http|
    puts '[Publisher] Connected.'.light_yellow
    puts "[Publisher] URL: #{uri.scheme}://#{uri.host}:#{uri.port}#{pub_uri}".light_yellow if opts[:verbose] > 2
    message = 'OPEN CHANNEL'
    puts "[Publisher] Sending: #{message}".light_yellow if opts[:verbose] > 2
    puts '[Publisher] First post.'.light_yellow
    http.request_post(URI.escape(pub_uri), message) do |response|
      puts "[Publisher] Feedback: #{response.read_body}".light_yellow if opts[:verbose] > 0
    end
  end
  puts '[Publisher] Disconnected.'.light_yellow

  buffer = ''
  loop do
    if flag_first_conn
      puts '[Publisher] Connecting...'.light_yellow if opts[:verbose] > 0
    else
      puts '[Publisher] Reconnecting...'.light_yellow if opts[:verbose] > 0
    end
    Net::HTTP.start(uri.host, uri.port) do |http|
      if flag_first_conn
        flag_first_conn = false
        puts '[Publisher] Connected.'.light_yellow
      else
        puts '[Publisher] Reconnected.'.light_yellow
      end
      puts "[Publisher] URL: #{uri.scheme}://#{uri.host}:#{uri.port}#{pub_uri}".light_yellow if opts[:verbose] > 2
      loop do
        send_timestamp = Time.now.strftime('%s.%L')
        message = "TS:#{send_timestamp}:"
        puts "[Publisher] Sending: #{message}".light_yellow if opts[:verbose] > 2
        http.request_post(URI.escape(pub_uri), message) do |response|
          puts "[Publisher] Feedback: #{response.read_body}".light_yellow if opts[:verbose] > 0
        end
        unless opts[:pubdelay] == 0
          puts "[Publisher] Sleeping #{opts[:pubdelay]} second#{pubdelay_plural}.".light_yellow if opts[:verbose] > 2
          sleep opts[:pubdelay]
        end
      end
    end
    puts '[Publisher] Disconnected.'.light_yellow
    sleep 1
  end
end

# Sub.
def subscriber(opts, uri)
  sub_uri = "#{opts[:sub]}/#{opts[:channel]}"
  flag_first_conn = true

  buffer = ''
  loop do
    if flag_first_conn
      puts '[Subscriber] Connecting...'.light_cyan if opts[:verbose] > 0
    else
      puts '[Subscriber] Reconnecting...'.light_cyan if opts[:verbose] > 0
    end
    Net::HTTP.start(uri.host, uri.port) do |http|
      if flag_first_conn
        flag_first_conn = false
        puts '[Subscriber] Connected.'.light_cyan
      else
        puts '[Subscriber] Reconnected.'.light_cyan
      end
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
                puts "[Subscriber] Writing last latency value to outfile: #{opts[:outfile]}".light_cyan if opts[:verbose] > 2
                File.open(opts[:outfile], 'wb').write("#{latency}\n")
              end
            end
          end
        end
      end
    end
    puts '[Subscriber] Disconnected.'.light_cyan
    sleep 1
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
    latency.rb http://www.nginxpushstream.org -vvvv

Options:
EOS
    on :c=, :channel=, 'Channel name.', :default => 'latency'
    on :d=, :pubdelay=, 'Publisher delay (in seconds) between messages.', :as => Float, :default => 1
    on :o=, :outfile=, 'Output file (write the last latency value to use in any external tool).'
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
  Process.waitall
  puts
  puts 'Exiting.'
  exit 0
end
