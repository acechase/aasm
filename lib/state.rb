module AASM
  module SupportingClasses
    class State
      attr_reader :name, :options

      def self.extract_delegate_state_association(state_name)
        state_name.to_s =~ /delegate_to_(.*)/ ? $1.to_sym : nil
      end

      def initialize(name, options={})
        @name, @options = name, options
        self.description_strings = options[:strings] if options.has_key?(:strings)
      end

      def ==(state)
        if state.is_a? Symbol
          name == state
        else
          name == state.name
        end
      end

      def call_action(action, record)
        action = @options[action]
        case action
        when Symbol, String
          record.send(action)
        when Proc
          action.call(record)
        end
      end

      def for_select
        [name.to_s.gsub(/_/, ' ').capitalize, name.to_s]
      end
      
      def description_strings
        @description_strings || {}
      end
      
      private
      def description_strings=(description_string_hash)
        @description_strings = description_string_hash
      end
    end
  end
end
