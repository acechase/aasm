require File.join(File.dirname(__FILE__), 'state_transition')

module AASM
  module SupportingClasses
    class Event
      attr_reader :name, :success
      
      def initialize(name, options = {}, &block)
        @name = name
        @success = options[:success]
        @transitions = []
        instance_eval(&block) if block
      end
      
      def fire(obj, to_state=nil, *args)
        transitions = @transitions.select { |t| t.from == obj.aasm_current_state }
        if transitions.size == 0
          msg = "#{obj.class.name}[#{obj.id}] - Event '#{name}' cannot transition from '#{obj.aasm_current_state}'"
          raise AASM::InvalidTransition, msg
        end

        next_state = nil
        transitions.each do |transition|
          next if to_state and !Array(transition.to).include?(to_state)
          if transition.perform(obj)
            next_state = to_state || Array(transition.to).first
            transition.execute(obj, *args)
            break
          end
        end
        next_state
      end

      def call_success(record)
        return unless @success
        case @success
        when Symbol, String
          record.send(@success)
        when Proc
          @success.call(record)
        end
      end
      
      # Finds the next state using the same approach as in #fire, but does not call the transitions execute callback
      def get_next_state(obj, to_state = nil, *args)
        transitions = @transitions.select { |t| t.from == obj.aasm_current_state }
        return nil if transitions.size == 0

        next_state = nil
        transitions.each do |transition|
          next if to_state and !Array(transition.to).include?(to_state)
          if transition.perform(obj)
            next_state = to_state || Array(transition.to).first
            break
          end
        end
        next_state
      end

      def transitions_from_state?(state)
        @transitions.any? { |t| t.from == state }
      end
      
      private
      def transitions(trans_opts)
        Array(trans_opts[:from]).each do |s|
          @transitions << SupportingClasses::StateTransition.new(trans_opts.merge({:from => s.to_sym}))
        end
      end
    end
  end
end
