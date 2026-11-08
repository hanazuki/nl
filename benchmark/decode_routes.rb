#!/usr/bin/env ruby

require 'bundler/setup'
require 'optparse'
require 'nl/linux'
require_relative 'lib/pcap'

module DecodeRoutesBenchmark
  class << self
    def message_class(header)
      case header.type
      when Nl::Linux::RtRoute::Messages::DumpGetrouteReply::TYPE
        Nl::Linux::RtRoute::Messages::DumpGetrouteReply
      when Nl::Linux::RtRoute::Messages::DumpGetrouteRequest::TYPE
        Nl::Linux::RtRoute::Messages::DumpGetrouteRequest
      else
        raise "no rt-route decoder for Netlink message type #{header.type}"
      end
    end

    def decode_all(datagrams, protocol, endpoint)
      count = 0
      datagrams.each do |datagram|
        Nl::Datagram.each_frame(datagram) do |header, payload|
          klass = header.type < Nl::Raw::NLMSG_MIN_TYPE ? nil : message_class(header)
          protocol.decode_frame(endpoint, header, payload, klass)
          count += 1
        end
      end
      count
    end

    def run(argv)
      options = {iterations: 1}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options] PCAP"
        opts.on('-n', '--iterations COUNT', Integer, 'Number of complete decode passes (default: 1)') do |count|
          raise OptionParser::InvalidArgument, 'must be positive' unless count.positive?

          options[:iterations] = count
        end
      end
      parser.parse!(argv)
      raise OptionParser::InvalidArgument, 'expected one pcap path' unless argv.one?

      datagrams = Pcap.open(argv.fetch(0)).to_a
      captured_bytes = datagrams.sum(&:size)
      protocol = Nl::Raw::Protocol.new(Nl::Linux::RtRoute::PROTONUM)
      endpoint = Nl::Raw::Endpoint.new(Nl::Linux::RtRoute)

      message_count = decode_all(datagrams, protocol, endpoint)
      warn "Loaded #{datagrams.size} datagrams, #{message_count} messages, " \
        "#{captured_bytes.fdiv(1024 * 1024).round(1)} MiB"

      measurements = Array.new(options[:iterations]) do
        GC.start
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        decoded = decode_all(datagrams, protocol, endpoint)
        raise "message count changed from #{message_count} to #{decoded}" unless decoded == message_count

        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      end

      sorted = measurements.sort
      middle = sorted.length / 2
      elapsed = if sorted.length.odd?
        sorted.fetch(middle)
      else
        (sorted.fetch(middle - 1) + sorted.fetch(middle)) / 2
      end
      label = options[:iterations] > 1 ? 'median: ' : ''
      puts format(
        "#{label}%.3f s, %.0f messages/s, %.1f MiB/s",
        elapsed,
        message_count / elapsed,
        captured_bytes.fdiv(1024 * 1024) / elapsed,
      )
    rescue OptionParser::ParseError => e
      warn e.message
      warn parser
      exit 2
    end
  end
end

DecodeRoutesBenchmark.run(ARGV)
