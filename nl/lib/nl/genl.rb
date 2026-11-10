require_relative 'genl/wire'
require_relative 'family'
require_relative 'raw'
require_relative 'genl/protocol'

module Nl
  # Generic Netlink families.
  module Genl
    # Base class for Generic Netlink families.
    class Family < Nl::Family
      # Returns the family-specific protocol version.
      #
      # @return [Integer] the protocol version
      # @rbs () -> Integer
      def self.version = self::VERSION

      # Opens a session for this Generic Netlink family.
      #
      # @overload open(resolver:, executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
      #   The caller is responsible for closing the session.
      #   @param [#call] resolver a callable that resolves a family name to {FamilyInfo}
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @return [Family] the opened family session
      # @overload open(resolver:, executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY, &block)
      #   The session is automatically closed after the block returns.
      #   @param [#call] resolver a callable that resolves a family name to {FamilyInfo}
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @yieldparam [Family] session the opened family session
      #   @return [Object] the value returned from the block
      # @rbs (resolver: ^(Client, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) -> (Nl::Family::Session & instance)
      #    | [R] (resolver: ^(Client, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(resolver:, executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
        begin
          owner = Client.new(resolver:, executor:, notification_capacity:)
          session = owner.family(self).extend(Nl::Family::Session)
        rescue Exception
          owner&.close
          raise
        end
        return session unless block_given?

        begin
          yield session
        ensure
          session.close
        end
      end
    end
  end
end

require_relative 'genl/client'
