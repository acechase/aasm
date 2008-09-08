require File.join(File.dirname(__FILE__), 'event')
require File.join(File.dirname(__FILE__), 'state')
require File.join(File.dirname(__FILE__), 'state_machine')
require File.join(File.dirname(__FILE__), 'persistence')

module AASM
  class InvalidTransition < RuntimeError
  end
  
  def self.included(base) #:nodoc:
    # TODO - need to ensure that a machine is being created because
    # AASM was either included or arrived at via inheritance.  It
    # cannot be both.
    base.extend AASM::ClassMethods
    AASM::Persistence.set_persistence(base)
    AASM::StateMachine[base] = AASM::StateMachine.new('')

    base.class_eval do
      def base.inherited(klass)
        AASM::StateMachine[klass] = AASM::StateMachine[self].dup
      end
    end
  end

  module ClassMethods
    def aasm_initial_state(set_state=nil)
      if set_state
        AASM::StateMachine[self].initial_state = set_state
      else
        AASM::StateMachine[self].initial_state
      end
    end
    
    def aasm_initial_state=(state)
      AASM::StateMachine[self].initial_state = state
    end
    
    def aasm_state(name, options={})
      sm = AASM::StateMachine[self]
      sm.create_state(name, options)
      sm.initial_state = name unless sm.initial_state
      add_string_methods(options[:strings].keys) if options.has_key?(:strings)

      define_method("#{name.to_s}?") do
        aasm_current_state == name
      end
    end
    
    def aasm_event(name, options = {}, &block)
      sm = AASM::StateMachine[self]
      
      unless sm.events.has_key?(name)
        sm.events[name] = AASM::SupportingClasses::Event.new(name, options, &block)
      end

      define_method("#{name.to_s}!") do |*args|
        aasm_fire_event(name, true, *args)
      end

      define_method("#{name.to_s}") do |*args|
        aasm_fire_event(name, false, *args)
      end
    end

    def aasm_states
      AASM::StateMachine[self].states
    end

    def aasm_events
      AASM::StateMachine[self].events
    end
    
    def aasm_states_for_select
      AASM::StateMachine[self].states.map { |state| state.for_select }
    end

    PREFIX_FOR_STRING_METHODS = "state_string_for_"
    def add_string_methods(method_identifiers)
      method_identifiers.each do |method_id|
        method_name = PREFIX_FOR_STRING_METHODS + method_id.to_s
        next if method_defined?(method_name)
        define_method(method_name) do
          aasm_deep_state_change_strings_for(method_id).andand.last
        end
      end
    end
    
  end

  # Instance methods
  def aasm_current_state
    return @aasm_current_state if @aasm_current_state

    if self.respond_to?(:aasm_read_state) || self.private_methods.include?('aasm_read_state')
      @aasm_current_state = aasm_read_state
    end
    return @aasm_current_state if @aasm_current_state
    self.class.aasm_initial_state
  end

  def aasm_active_state_machine_object
    unless association = SupportingClasses::State.extract_delegate_state_association( aasm_current_state )
      return self
    end
    if ! self.respond_to?(association)
      raise(StandardError, 
            'state machine is delegating to an association that this object does not know about.\n' +
            "#{self.class.name}[#{id}].#{association} does not exist.")
    end
    self.send(association).aasm_active_state_machine_object
  end

  def aasm_events_for_current_state
    aasm_events_for_state(aasm_current_state)
  end

  def aasm_events_for_state(state)
    events = self.class.aasm_events.values.select {|event| event.transitions_from_state?(state) }
    events.map {|event| event.name}
  end
  
  def aasm_deep_state_change_strings_for(key)
    aasm_deep_state_changes.map do |state_change| 
      active_sm = state_change.state_owner
      active_sm.send(:aasm_state_object_for_state, state_change.state).description_strings[key].andand.interpolate(binding)
    end.compact
  end
  
  private
  def aasm_current_state_with_persistence=(state)
    if self.respond_to?(:aasm_write_state) || self.private_methods.include?('aasm_write_state')
      aasm_write_state(state)
    end
    self.aasm_current_state = state
  end

  def aasm_current_state=(state)
    if self.respond_to?(:aasm_write_state_without_persistence) || self.private_methods.include?('aasm_write_state_without_persistence')
      aasm_write_state_without_persistence(state)
    end
    @aasm_current_state = state
  end

  def aasm_state_object_for_state(name)
    self.class.aasm_states.find {|s| s == name}
  end

  # fires the event identified by 'name'. If the state being entered is the same as the state being
  # exited some callbacks will not fire. Callback firing sequence is as follows:
  # 
  # current_state.exit        unless loopback
  # transition.on_transition
  # new_state.enter           unless loopback
  # self.aasm_event_fired
  # event.success             unless loopback
  # 
  def aasm_fire_event(name, persist, *args)
    event = self.class.aasm_events[name]
    is_loopback = event.get_next_state(self, *args) == aasm_current_state
    aasm_state_object_for_state(aasm_current_state).call_action(:exit, self) unless is_loopback
    new_state = event.fire(self, *args)   # N.B. still called when is_loopback == true
    
    unless new_state.nil?
      aasm_state_object_for_state(new_state).call_action(:enter, self) unless is_loopback
      
      if self.respond_to?(:aasm_event_fired)
        self.aasm_event_fired(self.aasm_current_state, new_state)
      end

      if persist
        self.aasm_current_state_with_persistence = new_state
        self.send(event.success) if event.success unless is_loopback
      else
        self.aasm_current_state = new_state
      end

      true
    else
      if self.respond_to?(:aasm_event_failed)
        self.aasm_event_failed(name)
      end
      
      false
    end
  end
end
