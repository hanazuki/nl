require_relative 'family'
require_relative 'raw/protocol'
require_relative 'raw/client'
require_relative 'message'

module Nl
  # Classic (Raw) Netlink families.
  module Raw
    # Base class for Raw Netlink families.
    class Family < Nl::Family
      # Opens a session for this raw Netlink family.
      #
      # @overload open(executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
      #   The caller is responsible for closing the session.
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @return [Family] the opened family session
      # @overload open(executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY, &block)
      #   The session is automatically closed after the block returns.
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @yieldparam [Family] session the opened family session
      #   @return [Object] the value returned from the block
      # @rbs (?executor: executor?, ?notification_capacity: Integer?) -> (Nl::Family::Session & instance)
      #    | [R] (?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
        session = build_session(executor:, notification_capacity:)
        return session unless block_given?

        begin
          yield session
        ensure
          session.close
        end
      end

      class << self
        # Builds a session that owns its underlying client.
        #
        # @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
        # @param [Integer] notification_capacity the maximum number of queued notifications
        # @return [Family] the opened family session
        # @rbs (executor: executor?, notification_capacity: Integer) -> (Nl::Family::Session & instance)
        private def build_session(executor:, notification_capacity:)
          owner = Client.new(protonum: self::PROTONUM, executor:, notification_capacity:)
          owner.family(self).extend(Nl::Family::Session)
        rescue Exception
          owner&.close
          raise
        end
      end
    end
  end
end
