require 'forwardable'

module DataMapper
  module Validations
    #
    # @author Guy van den Berg
    # @since  0.9
    class ContextualValidators
      extend Forwardable

      #
      # Delegators
      #

      def_delegators :@contexts, :empty?, :each
      include Enumerable

      attr_reader :contexts

      def initialize(model)
        @model      = model
        @contexts   = {}
      end

      #
      # API
      #

      # Return an array of validators for a named context
      #
      # @param  [String]
      #   Context name for which return validators
      # @return [Array<DataMapper::Validations::GenericValidator>]
      #   An array of validators
      def context(name)
        contexts[name] ||= OrderedSet.new
      end

      # Clear all named context validators off of the resource
      #
      def clear!
        contexts.clear
      end

      # Execute all validators in the named context against the target.
      # Load together any properties that are designated lazy but are not
      # yet loaded. Optionally only validate dirty properties.
      #
      # @param [Symbol]
      #   named_context the context we are validating against
      # @param [Object]
      #   target        the resource that we are validating
      # @return [Boolean]
      #   true if all are valid, otherwise false
      def execute(named_context, target)
        target.errors.clear!

        runnable_validators = context(named_context).select { |v| v.execute?(target) }

        # By default we start the list with the full set of runnable
        # validators.
        #
        # In the case of a new Resource or regular ruby class instance,
        # everything needs to be validated completely, and no eager-loading
        # logic should apply.
        #
        # In the case of a DM::Resource that isn't new, we optimize:
        #
        #   1. Eager-load all lazy, not-yet-loaded properties that need
        #      validation, all at once.
        #
        #   2. Limit run validators to
        #      - those applied to dirty attributes only,
        #      - those that should always run (presence/absence)
        #      - those that don't reference any real properties (field-less
        #        block validators, validations in virtual attributes)
        validators = 
          if target.kind_of?(DataMapper::Resource) && !target.new?
            validators_for_resource(target, runnable_validators)
          else
            runnable_validators.dup
          end

        validators.map { |validator| validator.call(target) }.all?
      end

      def validators_for_resource(resource, all_validators)
        attrs       = resource.attributes
        dirty_attrs = Hash[resource.dirty_attributes.map { |p, value| [p.name, value] }]
        validators  = all_validators.select { |v|
          !attrs.include?(v.field_name) || dirty_attrs.include?(v.field_name)
        }

        load_validated_properties(resource, validators)

        # Finally include any validators that should always run or don't
        # reference any real properties (field-less block vaildators).
        validators |= all_validators.select do |v|
          v.kind_of?(MethodValidator) ||
          v.kind_of?(PresenceValidator) ||
          v.kind_of?(AbsenceValidator)
        end

        validators
      end

      # Load all lazy, not-yet-loaded properties that need validation,
      # all at once.
      def load_validated_properties(resource, validators)
        properties = resource.model.properties

        properties_to_load = validators.map { |validator|
          properties[validator.field_name]
        }.compact.select { |property|
          property.lazy? && !property.loaded?(resource)
        }

        resource.__send__(:eager_load, properties_to_load)
      end

    end # module ContextualValidators
  end # module Validations
end # module DataMapper
