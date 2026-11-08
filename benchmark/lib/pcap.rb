class Pcap
  include Enumerable

  PCAP_HEADER_SIZE = 24
  PCAP_RECORD_HEADER_SIZE = 16
  SLL_HEADER_SIZE = 16
  LINKTYPE_NETLINK = 253

  BYTE_ORDERS = {
    "\xd4\xc3\xb2\xa1".b => 'V', # Microseconds, little-endian.
    "\xa1\xb2\xc3\xd4".b => 'N', # Microseconds, big-endian.
    "\x4d\x3c\xb2\xa1".b => 'V', # Nanoseconds, little-endian.
    "\xa1\xb2\x3c\x4d".b => 'N', # Nanoseconds, big-endian.
  }.freeze

  def self.open(path)
    new(path)
  end

  def initialize(path)
    @path = path
  end

  def each
    return enum_for(:each) unless block_given?

    File.open(@path, 'rb') do |pcap|
      header = read_exact(pcap, PCAP_HEADER_SIZE, 'pcap header')
      byte_order = BYTE_ORDERS[header.byteslice(0, 4)]
      raise 'not a classic pcap file' unless byte_order

      version_order = byte_order == 'V' ? 'v' : 'n'
      major, minor = header.byteslice(4, 4).unpack("#{version_order}2")
      raise "unsupported pcap version #{major}.#{minor}" unless [major, minor] == [2, 4]

      linktype = header.byteslice(20, 4).unpack1(byte_order) & 0xffff
      raise "expected LINKTYPE_NETLINK (#{LINKTYPE_NETLINK}), got #{linktype}" unless linktype == LINKTYPE_NETLINK

      record_number = 0

      until pcap.eof?
        record_number += 1
        record = read_exact(pcap, PCAP_RECORD_HEADER_SIZE, "pcap record #{record_number} header")
        _seconds, _fraction, captured_length, original_length = record.unpack("#{byte_order}4")
        if captured_length != original_length
          raise "pcap record #{record_number} is truncated (#{captured_length} of #{original_length} bytes)"
        end
        if captured_length < SLL_HEADER_SIZE
          raise "pcap record #{record_number} is shorter than its Linux cooked header"
        end

        packet = read_exact(pcap, captured_length, "pcap record #{record_number}")
        datagram = packet.byteslice(SLL_HEADER_SIZE..)
        yield IO::Buffer.for(datagram)
      end
    end
    self
  end

  private

  def read_exact(io, size, description)
    data = io.read(size)
    raise "truncated #{description}" unless data&.bytesize == size

    data
  end
end
